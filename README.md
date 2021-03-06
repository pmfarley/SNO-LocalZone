# SNO-LocalZone
Installing Single Node OpenShift (SNO) on AWS into a Local Zone using the OpenShift Assisted-Installer.
 
  REQUIREMENTS FOR INSTALLING ON A SINGLE NODE:  https://docs.openshift.com/container-platform/4.10/installing/installing_sno/install-sno-preparing-to-install-sno.html


## **PREREQUISITES:**
Single-Node OpenShift requires the following minimum host resources: 
- CPU: 8 CPU cores
- Memory: 32GB of RAM
- Storage: 120 GB 

r5d.2xlarge
- CPU: 8 vCPUs
- Memory: 64GB
- General Purpose SSD (gp2)
- 1 x 300 NVMe SSD

You'll also need to install the AWS CLI. https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html

![image](https://user-images.githubusercontent.com/48925593/140574901-4d6f8c39-6ffe-4e6a-87a5-5a9de79b6ab4.png)

If you've cloned or downloaded this repo, you can edit the variables in the provided script:  `deploySNOonAWS.sh`

Then to run the script with the following command:
 ```bash
 . ./deploySNOonAWS.sh
 ```

This script will execute the commands for Step 1 thru Step 4 below.  


## **STEP 1. CREATE THE VPC AND ASSOCIATED RESOURCES:**

**a. In order to get started, you need to first set some environment variables.**

  Run the following commands:

  ```bash
  export REGION="us-east-1"
  export LOCAL_ZONE="us-east-1-chi-1a"          #Chicago Local Zone
  export SNO_IMAGE_ID="ami-0ae9702360611e715"       #RHEL 8.4
  export SNO_INSTANCE_TYPE=m5.2xlarge 
  export KEY_NAME=pmf-key
   ```
Other variables that are created/used:
  ```bash
  $VPC_ID
  $IGW_ID
  $SNO_SG_ID
  $LZ_SUBNET_ID
  $LZ_RT_ID
  $SNO_INSTANCE_ID
   ```

**b. Use the AWS CLI to create the VPC.**

```bash
export VPC_ID=$(aws ec2 --region $REGION \
--output text create-vpc --cidr-block 10.0.0.0/16 \
--query 'Vpc.VpcId') && echo '\nVPC_ID='$VPC_ID
```


**c. Create an internet gateway and attach it to the VPC.**

```bash
export IGW_ID=$(aws ec2 --region $REGION \
--output text create-internet-gateway \
--query 'InternetGateway.InternetGatewayId') && echo '\nIGW_ID='$IGW_ID

aws ec2 --region $REGION  attach-internet-gateway \
 --vpc-id $VPC_ID  --internet-gateway-id $IGW_ID
```


## **STEP 2. DEPLOY THE SECURITY GROUP:**

In this section, you add one security group:
- `SNO SG`??allows SSH traffic and opens up ports (80, 443, 6443, 22623) and icmp from the Internet.

**a. Create the SNO security group along with ingress rules.**

Note: You can adjust the `???-cidr` parameter in the second command to restrict SSH access to only be allowed from your current IP address. 

This allows SSH and opening up other ports the SNO host communicates on (80, 443, 6443, 22623) and icmp.

```bash
export SNO_SG_ID=$(aws ec2 --region $REGION \
--output text create-security-group --group-name sno-sg \
--description "Security group for SNO host" --vpc-id $VPC_ID \
--query 'GroupId') && echo '\nSNO_SG_ID='$SNO_SG_ID

aws ec2 --region $REGION authorize-security-group-ingress \
--group-id $SNO_SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0

aws ec2 --region $REGION authorize-security-group-ingress \
--group-id $SNO_SG_ID --protocol tcp --port 6443 --cidr 0.0.0.0/0

aws ec2 --region $REGION authorize-security-group-ingress \
--group-id $SNO_SG_ID --protocol tcp --port 22623 --cidr 0.0.0.0/0

aws ec2 --region $REGION authorize-security-group-ingress \
--group-id $SNO_SG_ID --protocol tcp --port 80 --cidr 0.0.0.0/0

aws ec2 --region $REGION authorize-security-group-ingress \
--group-id $SNO_SG_ID --protocol tcp --port 443 --cidr 0.0.0.0/0

aws ec2 --region $REGION authorize-security-group-ingress \
--group-id $SNO_SG_ID --protocol icmp --port 0 --cidr 0.0.0.0/0
```

## **STEP 3. ADD THE SUBNETS AND ROUTING TABLES:**

In the following steps, you???ll create two subnets along with their associated routing tables and routes.

**a. Create the subnet for the Local Zone.**

```bash
export LZ_SUBNET_ID=$(aws ec2 --region $REGION \
--output text create-subnet --cidr-block 10.0.0.0/24 \
--availability-zone $LOCAL_ZONE --vpc-id $VPC_ID \
--query 'Subnet.SubnetId') && echo '\nLZ_SUBNET_ID='$LZ_SUBNET_ID
```

**e. Create the Local zone subnet route table and a route to direct traffic to the internet gateway.**

```bash
export LZ_RT_ID=$(aws ec2 --region $REGION \
--output text create-route-table --vpc-id $VPC_ID \
--query 'RouteTable.RouteTableId') && echo '\nLZ_RT_ID='$LZ_RT_ID 

aws ec2 --region $REGION  associate-route-table \
--subnet-id $LZ_SUBNET_ID --route-table-id $LZ_RT_ID \
--output text --query 'AssociationId'

aws ec2 --region $REGION  create-route --route-table-id $LZ_RT_ID \
--destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID
```

**f. Modify the local zone subnet to assign public IPs by default.**

```bash
aws ec2 --region $REGION  modify-subnet-attribute \
--subnet-id $LZ_SUBNET_ID  --map-public-ip-on-launch
```


## **STEP 4. DEPLOY THE SNO EC2 INSTANCE:**

With the VPC and underlying networking and security deployed, you can now move on to deploying your SNO EC2 instance. 

The SNO server is a `r5d.2xlarge` instance; running RHEL 8.4 AMI.

**a. Deploy the SNO EC2 instance.**

```bash
export SNO_INSTANCE_ID=$(aws ec2 --region $REGION run-instances  --instance-type $SNO_INSTANCE_TYPE \
--associate-public-ip-address --subnet-id $LZ_SUBNET_ID --output text --query Instances[*].[InstanceId] \
--image-id $SNO_IMAGE_ID --security-group-ids $SNO_SG_ID --key-name $KEY_NAME \
--block-device-mappings '[{"DeviceName": "/dev/sda1", "Ebs":{"VolumeSize": 120, "VolumeType": "gp2"}}]' \
--tag-specifications 'ResourceType=instance,Tags=[{Key="kubernetes.io/cluster/ocp-lz-sno",Value=shared}]') \
&& echo '\nSNO_INSTANCE_ID='$SNO_INSTANCE_ID
```



## **STEP 5. GENERATE DISCOVERY ISO FROM THE ASSISTED INSTALLER:**

Open the OpenShift Assisted Installer website: https://console.redhat.com/openshift/assisted-installer/clusters/. 
You will be prompted for your Red Hat ID and password to login.

**a. Select 'Create cluster'.**

 ![image](https://user-images.githubusercontent.com/48925593/166824453-61b32d61-fd75-451b-b0ba-234912e76f38.png)



**b. Enter the cluster name, and the base domain; then select 'Install single node OpenShift (SNO)' and 'OpenShift 4.10.11', and click 'Next'.**

 ![image](https://user-images.githubusercontent.com/48925593/166822431-0f9fa187-9a2d-42a7-bc1b-071e7ef5af00.png)




**c. Select 'Add host'.**

 ![image](https://user-images.githubusercontent.com/48925593/166823688-1a8312a4-ad2e-4054-a658-72f1e268e8b4.png)


 

**d. Select 'Minimal Image File' and 'Generate Discovery ISO'.**

![image](https://user-images.githubusercontent.com/48925593/166825485-2783d482-c14b-49c9-b64f-3763adac840b.png)



**e. Click on the 'Copy to clipboard' icon to the right of the 'Command to download the ISO'.**

This will be used in a later step from the SNO instance.

![image](https://user-images.githubusercontent.com/48925593/166824136-76cee7e8-ee98-4e19-9850-82098661d6a0.png)




**e. Click 'Close' to return to the previous screen.**


## **STEP 6. BOOT THE SNO INSTANCE FROM THE DISCOVERY ISO:**

AWS EC2 instances are NOT able to directly boot from an ISO image. So, we'll use the following steps to download the Discovery ISO image to the instance.
Then we'll add an entry to the grub configuration to allow it to boot from the image. 


**a. SSH into the SNO instance.**

```bash
ssh -i <your-sshkeyfile.pem> ec2-user@<ip address>
```


**b. Install wget and download the Discovery Image ISO.**

You'll need the download url provided previously in step 6e.  You'll need to edit the path and filename before you run the command to download the ISO file.  Notice that the file is being downloaded as `discovery-image.iso` into the `/var/tmp/` folder. 

```bash
sudo yum install wget -y

sudo wget -O /var/tmp/discovery-image.iso 'https://<long s3 url provided by AI SaaS>'
```


**c. Edit the grub configuration.**

Edit the 40_custom file.

```bash
sudo vi /etc/grub.d/40_custom
```
Add the following to the end of the file: 
 
```bash
menuentry "Discovery Image RHCOS" {
        set root='(hd0,2)'
        set iso="/var/tmp/discovery-image.iso"
        loopback loop ${iso}
        linux (loop)/images/pxeboot/vmlinuz boot=images iso-scan/filename=${iso} persistent noeject noprompt ignition.firstboot ignition.platform.id=metal coreos.live.rootfs_url='https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.9/4.9.0/rhcos-live-rootfs.x86_64.img'
        initrd (loop)/images/pxeboot/initrd.img (loop)/images/ignition.img (loop)/images/assisted_installer_custom.img
        }
```


**d. Save the grub configuration, and reboot the SNO instance.**

Execute these commands to generate and save the new menuentry.

```bash
sudo grub2-set-default 'Discovery Image RHCOS'
sudo grub2-mkconfig -o /boot/grub2/grub.cfg
sudo reboot
```


## **STEP 7. RETURN TO THE ASSISTED INSTALLER TO FINISH THE INSTALLATION:**

Return to the OpenShift Assisted Installer.
 
 **a. You should see the SNO instance displayed in the list of discovered servers. 
      From the _Host discovery_ menu, once the SNO instance is discovered, click 'Next'.**
 
  ![image](https://user-images.githubusercontent.com/48925593/143311949-ce94272a-0548-4b4e-9be2-9a76503617c2.png)

 
 **b. From the _Networking_ menu, select the discovered `network subnet`, and click on _Next_ to proceed.**

![image](https://user-images.githubusercontent.com/48925593/143313096-6ed9e605-50ee-43e1-8e05-9fd260c09d93.png)


![image](https://user-images.githubusercontent.com/48925593/143312805-d65410b7-0263-48bb-bbe1-56e885c99276.png)


**c. Review the configuration, and select _Install Cluster_.**

 ![image](https://user-images.githubusercontent.com/48925593/143313250-269de01d-5827-4001-bea4-69dde1982d2f.png)


**d. Monitor the installation progress.**

 ![image](https://user-images.githubusercontent.com/48925593/143313390-7b40a8a7-381c-4b97-908e-b6f4d14d6a68.png)
 
 ![image](https://user-images.githubusercontent.com/48925593/143314810-30cfc435-b66a-4069-a8fa-157e7e84fa1b.png)

 ![image](https://user-images.githubusercontent.com/48925593/143314890-e5389a58-fe0e-47f7-b863-7f317de7a7bf.png)

 ![image](https://user-images.githubusercontent.com/48925593/143315164-77fea973-cfc1-4c1c-8980-2b5852c052ab.png)

 ![image](https://user-images.githubusercontent.com/48925593/143316128-d1a5f578-4234-4acd-8ec1-86f7b52c0c49.png)


**e. Installation Complete.**

Upon completion, you'll see the summary of the installation, and you'll be able to download the kubeconfig file, 
and retreive the kubeadmin password.

 ![image](https://user-images.githubusercontent.com/48925593/143317424-36b69123-21d1-4213-83ac-26cb980f1e4f.png)




 
