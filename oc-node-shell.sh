#!/usr/bin/env sh
set -e

kubectl=kubectl
version=1.5.3
generator=""
node=""
nodefaultctx=0
nodefaultns=0
cmd='[ "nsenter", "--target", "1", "--mount", "--uts", "--ipc", "--net", "--pid", "--"'
if [ -t 0 ]; then
  tty=true
else
  tty=false
fi
while [ $# -gt 0 ]; do
  key="$1"

  case $key in
  -v | --version)
    echo "kubectl-node-shell $version"
    exit 0
    ;;
  --context)
    nodefaultctx=1
    kubectl="$kubectl --context $2"
    shift
    shift
    ;;
  --kubecontext=*)
    nodefaultctx=1
    kubectl="$kubectl --context=${key##*=}"
    shift
    ;;
  --kubeconfig)
    kubectl="$kubectl --kubeconfig $2"
    shift
    shift
    ;;
  --kubeconfig=*)
    kubectl="$kubectl --kubeconfig=${key##*=}"
    shift
    ;;
  -n | --namespace)
    nodefaultns=1
    kubectl="$kubectl --namespace $2"
    shift
    shift
    ;;
  --namespace=*)
    nodefaultns=1
    kubectl="$kubectl --namespace=${key##*=}"
    shift
    ;;
  --)
    shift
    break
    ;;
  *)
    if [ -z "$node" ]; then
      node="$1"
      shift
    else
      echo "exactly one node required"
      exit 1
    fi
    ;;
  esac
done

# Set the default context and namespace to avoid situations where the user switch them during the build process
[ "$nodefaultctx" = 1 ] || kubectl="$kubectl --context=$(${kubectl} config current-context)"
[ "$nodefaultns" = 1 ] || kubectl="$kubectl --namespace=$(${kubectl} config view --minify --output 'jsonpath={.contexts..namespace}')"

if [ $# -gt 0 ]; then
  while [ $# -gt 0 ]; do
    cmd="$cmd, \"$(echo "$1" | \
      awk '{gsub(/["\\]/,"\\\\&");gsub(/\x1b/,"\\u001b");printf "%s",last;last=$0"\\n"} END{print $0}' \
    )\""
    shift
  done
  cmd="$cmd ]"
else
  cmd="$cmd, \"bash\", \"-l\" ]"
fi

if [ -z "$node" ]; then
  echo "Please specify node name"
  exit 1
fi

image="${KUBECTL_NODE_SHELL_IMAGE:-dimaskiddo/debian:base}"
pod="nsenter-$(env LC_ALL=C tr -dc a-z0-9 </dev/urandom | head -c 6)"

# Check the node
$kubectl get node "$node" >/dev/null || exit 1

overrides="$(
  cat <<EOT
{
  "spec": {
    "nodeName": "$node",
    "hostPID": true,
    "hostNetwork": true,
    "containers": [
      {
        "securityContext": {
          "privileged": true
        },
        "image": "$image",
        "name": "nsenter",
        "stdin": true,
        "stdinOnce": true,
        "tty": $tty,
        "command": $cmd
      }
    ],
    "tolerations": [
      {
        "key": "CriticalAddonsOnly",
        "operator": "Exists"
      },
      {
        "effect": "NoExecute",
        "operator": "Exists"
      }
    ]
  }
}
EOT
)"

# Support Kubectl <1.18
m=$(kubectl version --client --output yaml | awk -F'[ :"]+' '$2 == "minor" {print $3+0}')
if [ "$m" -lt 18 ]; then
  generator="--generator=run-pod/v1"
fi

trap "EC=\$?; $kubectl delete pod $pod >&2 || true; exit \$EC" EXIT INT TERM

echo "spawning \"$pod\" on \"$node\"" >&2
$kubectl run --image "$image" --restart=Never --overrides="$overrides"  $([ "$tty" = true ] && echo -t) -i "$pod" $generator