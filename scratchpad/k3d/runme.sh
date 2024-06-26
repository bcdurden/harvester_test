#!/bin/bash

# set the mirror for docker.io to reference hauler
yq -n '.mirrors."docker.io".endpoint = ["http://localhost:5000"]' > /tmp/registries.yaml

# kickoff k3d with hauler-sourced image (note this requires localhost:5000 to be on your docker insecure regsitry list)
# also note that k3d is using host networking here. If you can't use host networking, you'll need to change localhost:5000 to your workstation IP and make the insecure registry change accordingly

# make local workspace directory a volume-mountable to k3d (available via hostpath inside the cluster)
mkdir workspace || true
k3d cluster create -i localhost:5000/rancher/k3s:v1.27.4-k3s1 --network host -v ${PWD}/workspace:/data --registry-config /tmp/registries.yaml
