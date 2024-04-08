import requests
import os

token = os.getenv('GITHUB_TOKEN')
repository = os.getenv('GITHUB_REPOSITORY')

url = f"https://api.github.com/repos/{repository}/environments"
headers = {
    'Authorization': f'token {token}',
    'Accept': 'application/vnd.github+json',
}

response = requests.get(url, headers=headers)
environments = response.json()

for env in environments['environments']:
    print(env['name'])
