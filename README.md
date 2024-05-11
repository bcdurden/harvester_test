# Quick Harvester Smoke Test

This script does a few basic actions on a Harvester cluster to ensure basic functionality using minimal tools. It is meant to either ensure your cluster is up and running in a usable state. Needed values can be defined in [test_config.yaml](./test_config.yaml).

## Requirements
* kubectl
* helm
* yq
* curl
* bash environment

## Tests
* Kubeconfig fetch via Harvester API
* VM Image creation
* Harvester Basic Network Configuration
* SSH Key creation
* VM Creation and ssh-connectivity verified
* VM Deletion and cleanup
* RKE2 cluster creation

## Howto
The script is simple to run, there are two required parameters: the admin `password` and the `vip` in your Harvester installation. You defined both of these when you installed Harvester onto your devices. 

Example of Tommy Tutone reaching Jenny's Harvester cluster, adjust your values accordingly

`./test.sh --password 'mypassword' --vip 86.75.30.9`

After tests have run, the cluster stays put so you can do further tests if you like. This cluster is 3 control plane nodes in a hybrid worker config, the best practice config for a Rancher MCM installation. Try installing Rancher MCM next!