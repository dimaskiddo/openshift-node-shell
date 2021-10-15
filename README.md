# OpenShift 3 Node Shell

A modified version of Kubernetes Node Shell or NShell or KubeCtl-Enter from [kvaps](https://github.com/kvaps/kubectl-node-shell) for OpenShift 3.

Since OpenShift 3 doesn't have ability to debug node `oc debug node/<node-name>` like OpenShift 4 then this can be a helper if something happened to you node and you can't access it from your secure shell



## Installation

Make sure you already have the same version of OpenShift Client and KubeCtl on you local like in the Master Node, or you can just straight through the installation in Master Node

```sh
oc version
kubectl version
```

Creating a project where the Node Shell pod will be deployed

```sh
oc adm new-project node-shell
```

Now we need to patch the project so the pod can deployed in everynode that we want, by default OpenShift only allowing pod to be deployed in spesific node with selector `region=primary`

```sh
oc patch namespace node-shell -p '{"metadata": {"annotations": {"openshift.io/node-selector": ""}}}'
```

Next we also need to grant a SCC privileged to our default service account in a project that we created before, in this case it will be `node-shell`

```sh
oc adm policy add-scc-to-user privileged -z default -n node-shell
```

Download the OpenShift Node Shell from this repository and set it as executable

```sh
wget -O /usr/local/bin/oc-node-shell https://raw.githubusercontent.com/dimaskiddo/openshift-node-shell/master/oc-node-shell.sh
chmod 755 /usr/local/bin/oc-node-shell
```

And here we are, ready to go!



## Usage

First get node name you want to enter

```sh
oc get nodes
```

After that to run the OpenShift Node Shell you need to run it under `node-shell` project that we are created before on the Installation step. You can run it with the following command

```sh
oc-node-shell -n node-shell <node-name>
```