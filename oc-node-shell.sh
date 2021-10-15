#!/usr/bin/env bash
set -e

kubectl=oc
version=1.5.3

generator=""
node=""

image="busybox:1.34.0"
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
    echo "oc-node-shell $version"
    exit 0
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

# Check if The Node Exist
$kubectl get node "$node" > /dev/null || exit 1

# Support Kubectl < 1.18
m=$(kubectl version --client --output yaml | awk -F'[ :"]+' '$2 == "minor" {print $3+0}')
if [ "$m" -lt 18 ]; then
  generator="--generator=run-pod/v1"
fi

overrides="$(
  cat << EOT
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
        "effect": "NoSchedule",
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

pod="nsenter-$(tr -dc a-z0-9 < /dev/urandom | head -c 6)"

trap "EC=\$?; $kubectl delete pod $pod >&2 || true; exit \$EC" EXIT INT TERM

echo "spawning \"$pod\" on \"$node\"" >&2
$kubectl run --image "$image" --restart=Never --overrides="$overrides"  $([ "$tty" = true ] && echo -t) -i "$pod" $generator
