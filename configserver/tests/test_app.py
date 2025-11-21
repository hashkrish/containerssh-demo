#!/usr/bin/env python3
"""
Unit tests for ContainerSSH Config Server
"""

import unittest
import json
import tempfile
import os
from unittest.mock import patch, mock_open
import sys

# Add parent directory to path to import app
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app import app, load_users_map


class ConfigServerTestCase(unittest.TestCase):
    """Test cases for config server endpoints"""

    def setUp(self):
        """Set up test client"""
        self.app = app
        self.app.config['TESTING'] = True
        self.client = self.app.test_client()

    def test_health_endpoint(self):
        """Test health check endpoint"""
        response = self.client.get('/health')
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.data)
        self.assertEqual(data['status'], 'healthy')

    def test_config_endpoint_missing_username(self):
        """Test config endpoint with missing username"""
        response = self.client.post('/config',
                                    data=json.dumps({}),
                                    content_type='application/json')
        self.assertEqual(response.status_code, 400)

    def test_config_endpoint_admin_user(self):
        """Test config endpoint with admin user pattern"""
        response = self.client.post('/config',
                                    data=json.dumps({'username': 'admin123'}),
                                    content_type='application/json')
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.data)
        self.assertEqual(data['config']['sshproxy']['server'], 'vm1')
        self.assertEqual(data['config']['sshproxy']['username'], 'admin123')

    def test_config_endpoint_ops_user(self):
        """Test config endpoint with ops user pattern"""
        response = self.client.post('/config',
                                    data=json.dumps({'username': 'ops-user'}),
                                    content_type='application/json')
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.data)
        self.assertEqual(data['config']['sshproxy']['server'], 'vm1')

    def test_config_endpoint_dev_user(self):
        """Test config endpoint with dev user pattern"""
        response = self.client.post('/config',
                                    data=json.dumps({'username': 'dev123'}),
                                    content_type='application/json')
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.data)
        self.assertEqual(data['config']['sshproxy']['server'], 'vm2')

    def test_config_endpoint_test_user(self):
        """Test config endpoint with test user pattern"""
        response = self.client.post('/config',
                                    data=json.dumps({'username': 'testuser'}),
                                    content_type='application/json')
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.data)
        self.assertEqual(data['config']['sshproxy']['server'], 'vm2')

    def test_config_endpoint_default_routing(self):
        """Test config endpoint with default routing"""
        response = self.client.post('/config',
                                    data=json.dumps({'username': 'someuser'}),
                                    content_type='application/json')
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.data)
        self.assertEqual(data['config']['sshproxy']['server'], 'vm1')

    @patch('app.load_users_map')
    def test_config_endpoint_explicit_mapping(self, mock_load):
        """Test config endpoint with explicit user mapping"""
        mock_load.return_value = {
            'alice': {
                'backend': 'vm2',
                'port': 22,
                'authorized_keys': []
            }
        }
        response = self.client.post('/config',
                                    data=json.dumps({'username': 'alice'}),
                                    content_type='application/json')
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.data)
        self.assertEqual(data['config']['sshproxy']['server'], 'vm2')
        self.assertEqual(data['config']['sshproxy']['port'], 22)
        self.assertEqual(data['config']['sshproxy']['username'], 'alice')

    @patch('app.load_users_map')
    def test_pubkey_endpoint_valid_key(self, mock_load):
        """Test pubkey endpoint with valid key"""
        test_key = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest123 test@example.com'
        mock_load.return_value = {
            'alice': {
                'backend': 'vm1',
                'authorized_keys': [test_key]
            }
        }

        response = self.client.post('/pubkey',
                                    data=json.dumps({
                                        'username': 'alice',
                                        'publicKey': test_key
                                    }),
                                    content_type='application/json')
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.data)
        self.assertTrue(data['success'])

    @patch('app.load_users_map')
    def test_pubkey_endpoint_invalid_key(self, mock_load):
        """Test pubkey endpoint with invalid key"""
        mock_load.return_value = {
            'alice': {
                'backend': 'vm1',
                'authorized_keys': ['ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest123 test@example.com']
            }
        }

        response = self.client.post('/pubkey',
                                    data=json.dumps({
                                        'username': 'alice',
                                        'publicKey': 'ssh-ed25519 AAAAC3InvalidKey invalid@example.com'
                                    }),
                                    content_type='application/json')
        self.assertEqual(response.status_code, 403)

    @patch('app.load_users_map')
    def test_pubkey_endpoint_unknown_user(self, mock_load):
        """Test pubkey endpoint with unknown user"""
        mock_load.return_value = {}

        response = self.client.post('/pubkey',
                                    data=json.dumps({
                                        'username': 'unknownuser',
                                        'publicKey': 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest123 test@example.com'
                                    }),
                                    content_type='application/json')
        self.assertEqual(response.status_code, 403)


class LoadUsersMapTestCase(unittest.TestCase):
    """Test cases for load_users_map function"""

    @patch('builtins.open', new_callable=mock_open, read_data='{"alice": {"backend": "vm1"}}')
    @patch('os.path.exists', return_value=True)
    def test_load_users_map_success(self, mock_exists, mock_file):
        """Test successful loading of users map"""
        result = load_users_map()
        self.assertEqual(result, {'alice': {'backend': 'vm1'}})

    @patch('os.path.exists', return_value=False)
    def test_load_users_map_file_not_exists(self, mock_exists):
        """Test loading users map when file doesn't exist"""
        result = load_users_map()
        self.assertEqual(result, {})

    @patch('builtins.open', side_effect=Exception('Test error'))
    @patch('os.path.exists', return_value=True)
    def test_load_users_map_error(self, mock_exists, mock_file):
        """Test loading users map with error"""
        result = load_users_map()
        self.assertEqual(result, {})


if __name__ == '__main__':
    unittest.main()
