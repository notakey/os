#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

tag="${1-}"
DEST_REPO=repo.notakey.com

usage() {
	echo "  Synces OS base list of packages in repository under rancher/ namesapce on hub.docker.com"
	echo "  and publishes them under DEST_REPO repository. "
	
	echo " "
	
	echo "  USAGE: $0 <ros_tag>"
	echo "  "
	echo "     <ros_tag> - rancherOS version tag to sync"
	exit 1
}

if [ -z "$tag}" ]; then
	usage
fi


# _img=(os-bootstrap os-base os-acpid os-console os-logrotate os-syslog)
_img=()

for _img_line in "${_img[@]}"; do
	echo "Syncing image $_img_line"
	
	_docker_img="rancher/${_img_line}:${tag}"
	_ntk_img="${DEST_REPO}/ros-${_img_line}:${tag}"

	echo -n "Pulling $_docker_img... "
	docker pull "$_docker_img" >/dev/null
	echo "done"
	
	echo -n "Tagging $_ntk_img... "
	docker tag "$_docker_img" "$_ntk_img" >/dev/null
	echo "done"

	echo -n "Pushing $_ntk_img... "
	docker push "$_ntk_img" >/dev/null
	echo "done"
done
