#!/bin/bash

# parse args
CONFIG_FILE=test_config.yaml
while [[ $# -gt 0 ]] && [[ "$1" == "--"* ]] ;
do
    opt="$1";
    shift;              
    case "$opt" in
        "--password" )
           PASSWORD="$1"; shift;;
        "--password="* )    
           PASSWORD="${opt#*=}";;
        "--vip" )
           VIP="$1"; shift;;
        "--vip="* )
           VIP="${opt#*=}";;
        "--remove" )
           REMOVE=true;;
        "--config" )
           CONFIG_FILE="$1"; shift;;
        *) echo >&2 "Invalid option: $@"; exit 1;;
   esac
done

# get token
TOKEN=$(curl -sk -X POST https://$VIP/v3-public/localProviders/local?action=login -H 'content-type: application/json' -d '{"username":"admin","password":"'$PASSWORD'"}' | jq -r '.token')
if [[ $TOKEN == "null" ]]; then
    echo "Failed to get token, is the password and VIP correct?"
fi

# get kubeconfig
WORK_DIR=$(mktemp -d)
curl -sk https://$VIP/v1/management.cattle.io.clusters/local?action=generateKubeconfig -H "Authorization: Bearer ${TOKEN}" -X POST -H 'content-type: application/json' | jq -r .config > $WORK_DIR/config
chmod 600 $WORK_DIR/config
export KUBECONFIG=$WORK_DIR/config

### RUN TESTS

## VM Images
# deploy all vm images
echo "Testing VM image create"
VMS=$(yq '.vm_images[].name' ${CONFIG_FILE})
for vm in ${VMS}; do
    export OS_TYPE=$(yq '.vm_images[] | select(.name == "'$vm'") | .os_type' ${CONFIG_FILE})
    export IMAGE_URL=$(yq '.vm_images[] | select(.name == "'$vm'") | .url' ${CONFIG_FILE})
    export IMAGE_NAME=$vm
    # run envvars through subst
    cat templates/vmi_template.yaml | envsubst | kubectl apply -f -
    sleep 1
done

## VM Networks
# deploy all networks
echo "Testing Network create"
NETWORKS=$(yq '.networks[].name' ${CONFIG_FILE})
for network in ${NETWORKS}; do
    if ! kubectl get network-attachment-definitions $network > /dev/null 2>&1; then
    export CONFIG=$(yq '.networks[] | select(.name == "'$network'") | .config' ${CONFIG_FILE})
    export NETWORK_NAME=$network
    # run envvars through subst
    cat templates/network_template.yaml | envsubst | kubectl apply -f -
    fi
done

## SSH Key
echo "Testing SSH Key create"
rm -rf /tmp/test_key &> /dev/null
ssh-keygen -t rsa -N "" -f /tmp/test_key
export PUB_KEY=$(cat /tmp/test_key.pub)
cat templates/sshkey_template.yaml | envsubst | kubectl apply -f -

# wait for VM images
for vm in ${VMS}; do
    echo "Waiting for $vm image to become ready"
    until [[ $(kubectl get virtualmachineimage $vm -o yaml | yq .status.progress) == "100" ]]; do printf "."; sleep 5; done
    echo "$vm image is ready"
done

# Create VMs
echo "Testing VM creation for each image"
VMS=$(yq '.vms[].name' ${CONFIG_FILE})
for vm in ${VMS}; do
    if ! kubectl get vm $vm > /dev/null 2>&1; then
    export VM_NAME=$vm
    export VM_IMAGE=$(yq '.vms[] | select(.name == "'$vm'") | .image' ${CONFIG_FILE})
    export NETWORK_NAME=$(yq '.vms[] | select(.name == "'$vm'") | .network' ${CONFIG_FILE})
    # run envvars through subst
    cat templates/vm_template.yaml | envsubst | kubectl apply -f -
    fi
done

## Do some VM validation
sleep 1

## SSH into each VM and run test command
echo "Testing VM running state"
VMS=$(yq '.vms[].name' ${CONFIG_FILE})
for vm in ${VMS}; do
    if kubectl get vm $vm > /dev/null 2>&1; then
        # wait for VM
        echo "Waiting for $vm"
        until [[ $(kubectl get vm $vm -o yaml | yq '.status.ready') == "true" ]]; do printf "."; sleep 5; done
        echo "$vm has started, waiting for IP to post"
        until [[ $(kubectl get vmi $vm -o yaml | yq '.status.interfaces[0].ipAddress') != "null" ]]; do printf "."; sleep 5; done
        IP=$(kubectl get vmi $vm -o yaml | yq '.status.interfaces[0].ipAddress')
        echo "$vm available at $IP"
        USERNAME=$(yq '.vms[] | select(.name == "'$vm'") | .default_user' ${CONFIG_FILE})
        COMMAND=$(yq '.vms[] | select(.name == "'$vm'") | .test_command' ${CONFIG_FILE})
        ssh -i /tmp/test_key -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $USERNAME@$IP ''$COMMAND''
        if [ ! $? ]; then 
            echo "SSH Test Failed, check the default user field and ensure VM is not stuck"
        fi
    else
        echo "Did not find VM named $vm, did something go wrong?"
        exit -1
    fi
done

## Delete VMs
echo "Cleaning up"
VMS=$(yq '.vms[].name' ${CONFIG_FILE})
for vm in ${VMS}; do
    if kubectl get vm $vm > /dev/null 2>&1; then
        kubectl delete vm $vm --force || true
        kubectl get pvc | awk '/'$vm'/{print $1}' | xargs kubectl delete pvc || true
    fi
done

## Create RKE2 cluster
yq '.cluster' ${CONFIG_FILE} | helm upgrade --install rke2 charts/rke2 -f - --set ssh_pub_key="$PUB_KEY" --wait
NODE_NAME="mycluster-cp-0"
VIP=$(yq '.cluster.control_plane.vip' ${CONFIG_FILE})
echo "Waiting for $NODE_NAME to start"
until [[ $(kubectl get vm $NODE_NAME -o yaml | yq '.status.ready') == "true" ]]; do printf "."; sleep 5; done

echo "$NODE_NAME has started, waiting for IP to post"
until [[ $(kubectl get vmi $NODE_NAME -o yaml | yq '.status.interfaces[0].ipAddress') != "null" ]]; do printf "."; sleep 5; done
IP=$(kubectl get vmi $NODE_NAME -o yaml | yq '.status.interfaces[0].ipAddress')
echo "IP posted"

# create LB (since harvester has invoked tight coupling on LB for now)
yq '.cluster' ${CONFIG_FILE} | helm upgrade --install rke2-lb charts/lb -f -

echo "Waiting for Cloud-Init on $NODE_NAME : $IP"
ssh -i /tmp/test_key -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@${IP} "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do printf '.'; sleep 5; done"

echo "Fetching kubeconfig from $NODE_NAME : $IP"
ssh -i /tmp/test_key -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@${IP} "sudo cat /etc/rancher/rke2/rke2.yaml" 2> /dev/null | \
sed "s/127.0.0.1/${VIP}/g" > kube.yaml
echo "Sleeping to let nodes join"
sleep 20
kubectl --kubeconfig kube.yaml get nodes

echo "Tests finished"
rm -rf ${WORK_DIR}

echo "Check the cluster via: kubectl --kubeconfig kube.yaml get nodes"
echo ""
echo "Delete the cluster with: helm delete rke2-lb; helm delete rke2-lb; helm delete rke2"
echo "Sometimes the loadbalancer fails deletion the first time due to order of operations and helm being kinda dumb about that stuff"
echo "Also delete the PVCs since Harvester does not auto-clean volumes upon deletion via the CRs:"
echo "kubectl get pvc | awk '/mycluster/{print $1}' | xargs kubectl delete pvc"