# Tekton 

Install tekton with `kubectl apply -f release.yaml`.  This is a pretty static install of basic tekton. 

Tekton has a lot of features and is a kubernetes-analogue to Concourse but now the whole management backplane runs in Kubernetes itself and does not use garden containers. This usage of it is extremely simple, there are no webhooks or pipelines involved. A `Task` object is created that defines arbitrary bash scripts or `steps`. Each uses an image to run the commands within much like Concourse did.

Tekton needs a Kubernetes cluster to run within but this setup is mostly location agnostic. It's only real dependency is that a `/data` directory exists on the Kubernetes host it runs on and that it has access to it. This is where the Tekton workspace will live so each step can pull data from previous steps if necessary. Typically I use K3D for the cluster as it is very fast to spin up with minimal resources but KinD can also work. See the K3D directory for a script that installs K3D.


# Tekton Task Create
Create the task object via the [harvester_config.yaml](./harvester_config.yaml) file. The parameters at the top of this file can be considered defaults. Creating a task object does NOT run the task, think of it as a template.

```yaml
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: harvester-prep
spec:
  params:
  - name: key
    type: string
  - name: ip
    type: string
  - name: vip
    type: string
  - name: ui-password
    type: string
    default: rfedrfed8675309
  - name: prefix
    type: string
    default: ""
```


There are some Tekton-isms in the scripts within this file. Most notably is notation such as `$(workspaces.harvester-workspace.path)` or `$(params.vip)`. These values are considered Tekton templated values and will be filled in when the task is run (no need for quote capture from bash)

## Tekton Image
Each step uses a container image to do execution. I've created one specifically for my purposes in my overall automation framework at `bcdurden/ubuntu-fulcrum`. I'm including the `Dockerfile` used to build this image. If you do change it, ensure the iamge entries in the `TaskRun` objects are changed to compensate. Just do a search/replace as the workspace init container also uses this.

```yaml
image: bcdurden/ubuntu-fulcrum
```

# Tekton Run
Execute the above task by creating a `TaskRun` object. See [run.yaml](./run.yaml) as an example. Note the params at the top fill in specific values.

```yaml
---
apiVersion: tekton.dev/v1beta1
kind: TaskRun
metadata:
  name: harvester-prep-run
spec:
  params:
  - name: key
    value: "key"
  - name: ip
    value: "10.10.0.16"
  - name: vip
    value: "10.10.0.15"
  - name: prefix
    value: "set -x"
  - name: ui-password
    value: "rfedrfed8675309"
  taskRef:
    name: harvester-prep
  workspaces:
    - name: harvester-workspace 
      emptyDir: {}      
```

# Tekton Status
When running, Tekton creates a pod for the task and each pod will have X containers within it representing the various stages of execution. The containers will not run until the first finishes so they will just sit and wait. Tekton automatically does this so there is no need to inject artificial waits. 

When using K3D, a local directory is mounted into the K3D node at `/data` and is where all data can be stored/shared from each script. 

# Console Output

Creating K3D:

```console
$ ./runme.sh 
mkdir: cannot create directory ‘workspace’: File exists
INFO[0000] [SimpleConfig] Hostnetwork selected - disabling injection of docker host into the cluster, server load balancer and setting the api port to the k3s default 
WARN[0000] No node filter specified                     
INFO[0000] [ClusterConfig] Hostnetwork selected - disabling injection of docker host into the cluster, server load balancer and setting the api port to the k3s default 
INFO[0000] Prep: Network                                
INFO[0000] Re-using existing network 'host' (3baf71fea93fdcfc2a3389022088f9950e8004638e0165050531814d34512b7b) 
INFO[0000] Created image volume k3d-k3s-default-images  
INFO[0000] Starting new tools node...                   
INFO[0000] Starting Node 'k3d-k3s-default-tools'        
INFO[0001] Creating node 'k3d-k3s-default-server-0'     
INFO[0001] Pulling image 'rancher/k3s:v1.27.4-k3s1'     
INFO[0001] Using the k3d-tools node to gather environment information 
INFO[0002] Starting cluster 'k3s-default'               
INFO[0002] Starting servers...                          
INFO[0002] Starting Node 'k3d-k3s-default-server-0'     
INFO[0005] All agents already running.                  
INFO[0005] All helpers already running.                 
INFO[0005] Cluster 'k3s-default' created successfully!  
INFO[0005] You can now use it like this:                
kubectl cluster-info
```

Installing Tekton:

```console
$ kubectl apply -f release.yaml 
namespace/tekton-pipelines created
clusterrole.rbac.authorization.k8s.io/tekton-pipelines-controller-cluster-access created
clusterrole.rbac.authorization.k8s.io/tekton-pipelines-controller-tenant-access created
...
configmap/hubresolver-config created
deployment.apps/tekton-pipelines-remote-resolvers created
service/tekton-pipelines-remote-resolvers created
horizontalpodautoscaler.autoscaling/tekton-pipelines-webhook created
deployment.apps/tekton-pipelines-webhook created
service/tekton-pipelines-webhook created
```

Creating `TaskRun` object:

```console
$ kubectl apply -f harvester_config.yaml 
task.tekton.dev/harvester-prep created
$ kubectl get Task
NAME             AGE
harvester-prep   17s
```

Running `Task:

```console
$ kubectl apply -f run.yaml 
taskrun.tekton.dev/harvester-prep-run created
$ kubectl get po
NAME                     READY   STATUS     RESTARTS   AGE
harvester-prep-run-pod   0/3     Init:1/2   0          6s
$ kubectl get po
NAME                     READY   STATUS    RESTARTS   AGE
harvester-prep-run-pod   3/3     Running   0          21s
```

Getting Status (note I have no endpoint listening at .15)

```console
$ kubectl logs harvester-prep-run-pod 
Defaulted container "step-configure-password" out of: step-configure-password, step-fetch-kubeconfig, sidecar, prepare (init), place-scripts (init)

Waiting for Harvester to be available
+ HARVESTER_URL=10.10.0.15
+ printf \nWaiting for Harvester to be available\n
+ curl -sk --write-out %{http_code} --output /dev/null https://10.10.0.15/v3-public
+ grep 200
+ wc -l
+ [ 0 = 1 ]
+ sleep 10
+ printf .
+ curl -sk --write-out %{http_code} --output /dev/null https://10.10.0.15/v3-public
+ grep 200
+ wc -l
+ [ 0 = 1 ]
+ sleep 10
+ printf .
+ curl -sk --write-out %{http_code} --output /dev/null https://10.10.0.15/v3-public
+ grep 200
+ wc -l
```
