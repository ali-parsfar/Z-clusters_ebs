#!/bin/bash
# Description = This bash script > With using eksctl , creates a simple eks cluster with AWS-EBS-CSI-Driver .
# HowToUse = " % ./run.sh| tee -a output.md "
# Duration = Around 15 minutes
# https://github.com/kubernetes-sigs/aws-ebs-csi-driver


### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
### Variables:
export REGION=us-east-1
export CLUSTER_NAME=awsebscsi
export CLUSTER=$CLUSTER_NAME
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export ACC=$AWS_ACCOUNT_ID
export AWS_DEFAULT_REGION=$REGION
# export role_name=AmazonEKS_EFS_CSI_DriverRole_$CLUSTER_NAME


echo " 
### PARAMETERES IN USER >>> 
CLUSTER_NAME=$CLUSTER_NAME  
REGION=$REGION 
AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID

"

if [[ $1 == "cleanup" ]] ;
then 


### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
echo " 
### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
 ### 0- Cleanup EFS file system for eks-nfs :
 "
# Do Cleanup


exit 1
fi;



### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
echo " ### 1- Create cluster "

eksctl create cluster  -f - <<EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: $CLUSTER
  region: $REGION

managedNodeGroups:
  - name: mng
    privateNetworking: true
    desiredCapacity: 2
    instanceType: t3.medium
    labels:
      worker: linux
    maxSize: 2
    minSize: 0
    volumeSize: 20
    ssh:
      allow: true
      publicKeyPath: AliSyd

kubernetesNetworkConfig:
  ipFamily: IPv4 # or IPv6

addons:
  - name: vpc-cni
  - name: coredns
  - name: kube-proxy
  - name: aws-ebs-csi-driver

iam:
  withOIDC: true

iamIdentityMappings:
  - arn: arn:aws:iam::$ACC:user/Ali
    groups:
      - system:masters
    username: admin-Ali
    noDuplicateARNs: true # prevents shadowing of ARNs

cloudWatch:
  clusterLogging:
    enableTypes:
      - "*"

EOF

### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
echo " ### 2- kubeconfig  : "
aws eks update-kubeconfig --name $CLUSTER --region $REGION


### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
echo " ### 3- Check cluster node and infrastructure pods  : "
kubectl get node
kubectl -n kube-system get pod 

### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
echo " ### 4- Creating storag class = ebs-sc : "
kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-sc
provisioner: ebs.csi.aws.com
volumeBindingMode: Immediate
# volumeBindingMode: WaitForFirstConsumer
EOF


### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
echo " ### 5- Creating dynamic volume claim = ebs-claim  : "
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ebs-claim
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ebs-sc
  resources:
    requests:
      storage: 1Gi
EOF
kubectl describe pvc > pvc-0-describe.yaml

### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
echo " ### 6- Creating pod = app   : "
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: app
spec:
  containers:
  - name: app
    image: centos
    command: ["/bin/sh"]
    args: ["-c", "while true; do echo \`date -u\` >> /data/out.txt; sleep 5; done"]
    volumeMounts:
    - name: persistent-storage
      mountPath: /data
  volumes:
  - name: persistent-storage
    persistentVolumeClaim:
      claimName: ebs-claim
EOF

### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
echo " ### 7- Recording Node , csiNode , SC , PVC , PV , POD  :"
kubectl get node -o yaml > node-oyaml.yaml
kubectl get csinode -o yaml > csinode-0-oyaml.yaml
kubectl get csidriver -o yaml > csidriver-oyaml.yaml
kubectl describe csidriver > csidriver-describe.yaml
kubectl get sc -o yaml > sc-oyaml.yaml
kubectl get pv -o yaml > pv-oyaml.yaml
kubectl get pvc -o yaml > pvc-oyaml.yaml
kubectl get pod -o yaml > pod-oyaml.yaml
kubectl get VolumeAttachment -o yaml > volumeattachment-oyaml.yaml
kubectl describe node  > node-describe.yaml
kubectl describe csinode > csinode-0-describe.yaml
kubectl describe sc > sc-describe.yaml
kubectl describe pv > pv-describe.yaml
kubectl describe pvc > pvc-describe.yaml
kubectl describe pod > pod-describe.yaml
sleep 60
kubectl get event > event.txt   

kubectl -n kube-system logs -l app=ebs-csi-controller -c csi-provisioner > log__csi-provisioner.log
kubectl -n kube-system logs -l app=ebs-csi-controller -c csi-attacher > log__csi-attacher.log
kubectl -n kube-system logs -l app=ebs-csi-controller -c ebs-plugin > log__ebs-ctl-plugin.log
kubectl -n kube-system logs -l app=ebs-csi-node  -c  node-driver-registrar  > log__node-driver-registrar.log
kubectl -n kube-system logs -l app=ebs-csi-node -c ebs-plugin > log__ebs-node-plugin.log      

kubectl describe csinode > csinode-describe.yaml
kubectl get csinode -o yaml > csinode-oyaml.yaml
