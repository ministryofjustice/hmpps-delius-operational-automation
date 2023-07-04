# Steps to run Ansible locally

0. Pre-req
```
cd ansible
python=$(which python3)
```

1. Install Ansible
```
$python -m pip install ansible==6.0.0 (ansible core 2.13)
```

2. Create virtual environment
```
mkdir ./python-env && cd $_
$python -m venv ansible
source ansible/bin/activate
```

3. Install dependencies
```
cd ../
python -m pip install -r requirements.txt
ansible-galaxy role install -r requirements.yml
ansible-galaxy collection install -r requirements.yml
```

4. Sign in to AWS
Should be able to run
```
ansible-inventory --graph
```

5. Run ansible
```
no_proxy="*" ansible-playbook playbooks/test/playbook.yml --extra-vars "@group_vars/dev.yml" -i "hosts/"
```

6. Finish / tidy up
Remove python virtual environment
```
deactivate 
```
