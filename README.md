aws-ec2-ebs-snapshot-check-bash
===================================

####Amazon Web Services EBS Snapshot Verification - Bash Script

Written by  **[Casey Labs Inc.] (http://www.caseylabs.com)** and **[Bleeding Edge Solutions] (http://www.bledsol.net)**
*Contact us for all your Amazon Web Services Consulting needs!*

===================================

**How it works:**
check-snapshots.sh will:
- Gather a list of all running EC2 instances, and of all EBS volumes attached to those instances.
- Check the snapshots times associated with each in-use EBS volume, and alert if there are no recent snapshots.

Pull requests greatly welcomed!

===================================

**REQUIREMENTS**

**IAM User:** This script requires that a new user (e.g. ebs-snapshot) be created in the IAM section of AWS.   
Here is a sample IAM policy for AWS permissions that this new user will require:

```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "Stmt1426256275000",
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeInstances",
                "ec2:DescribeSnapshots",
                "ec2:DescribeVolumes"
            ],
            "Resource": [
                "*"
            ]
        }
    ]
}
```
<br />

**AWS CLI:** This script requires the AWS CLI tools to be installed.

Linux install instructions for AWS CLI:
 - Make sure Python pip is installed (e.g. yum install python-pip, or apt-get install python-pip)
 - Then run: 
```
pip install awscli
```
Once the AWS CLI has been installed, you'll need to configure it with the credentials of the IAM user created above:
(Note: this step can be skipped if you have an IAM Role setup for your instance to use the IAM policy listed above.)

```
sudo aws configure
```

_Access Key & Secret Access Key_: enter in the credentials generated above for the new IAM user.

_Region Name_: the region that this instance is currently in: ```i.e. us-east-1, eu-west-1, etc.```

_Output Format_: enter "text"


Then copy this Bash script to /opt/aws/ebs-snapshot.sh and make it executable:
```
chmod +x /opt/aws/check-snapshots.sh
```

To manually test the script:
```
sudo /opt/aws/check-snapshots.sh
```
