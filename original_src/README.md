# hashcat-aws
hashcat on aws

Setup:
1. Edit env/hosts (see env/hosts.example)
2. Edit group_vars/all (see group_vars/all.example)
3. Set up your S3 bucket as follows:
    A. MYBUCKETNAME/hashes/crackme (this is the hashcat-ready file that needs crack'n)
    B. MYBUCKETNAME/hashes/crackme.type (this is the integer for hashcat to tell it the type; i.e. 22000 for WPA2)
4. Create an AWS keypair and be sure to reference it in the env/hosts and group_vars/all files
5. Create ~/.aws/credentials 

To deploy, run:
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook hashcat.yml -i env/hosts -e group_vars/all 

To destroy *ALL* instances, run:
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook hashcat-destroy.yml -i env/hosts -e group_vars/all

If not using the default/only AWS profile in ~/.aws/credentials, you can prepend: AWS_PROFILE=myawsprofile

--

On successful run of hashcat.yml the instance will self terminate. If not use the hashcat-destroy.yml to destroy all instances.
