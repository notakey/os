#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

usage() {
	echo "  Synces packages listen in repository under rancher/ namesapce on hub.docker.com"
	echo "  and publishes them under DEST_REPO repository. "
	
	echo " "
	
	echo "  USAGE: $0 <branch> <auth> [<repo_url>] [<suffix>] [<kernel_ver>]"
	echo "  "
	echo "     <branch> - select branch to sync packages from"
	echo "     <auth> - username and password in format user:pass for dest repo"
	exit 1
}

if [ -z "${1-}" ]; then
	usage
fi

BRANCH="${1}"

# coud be _arm / _arm64
SUFFIX=""
# 4.9.24-rancher - 4.1 applianace
# 4.9.49-rancher - 4.2 appliance
KERNEL_VERSION="4.9.49-rancher"

REPO_AUTH="${2-}"
DEST_REPO=repo.notakey.com

_remote_tag_checksum() {
  local _tag; _tag="${3:-latest}"
  local _image; _image="${2}"
  local _token
  local _proxy_cfg; _proxy_cfg=""
  local _token_cmd
  local _cfgstatus; _cfgstatus="${1:-repo.notakey.com}"
  
  if [ "$_cfgstatus" == "hub.docker.com" ]; then  
  	   ## Tokens used only if using hub.docker.com
  	  _token_cmd="curl $_proxy_cfg 'https://auth.docker.io/token?service=registry.docker.io&scope=repository:rancher/${_image}:pull'"

  	  _token=$( eval $_token_cmd 2>/dev/null | jq -r .token )
	  if [ -z "$_token" ]; then
	  	  echo ""
	  	  return 
	  fi
  
  	  _tag_cmd="curl -s --fail $_proxy_cfg 
          -H \"Accept: application/vnd.docker.distribution.manifest.v2+json\" 
          -H \"Authorization: Bearer $_token\" 
          --head \"https://registry.hub.docker.com/v2/rancher/${_image}/manifests/$_tag\""
  else        
  	  _repo_auth="-u \"$REPO_AUTH\""
  	  
	  _tag_cmd="curl -s --fail $_proxy_cfg 
			  -H \"Accept: application/vnd.docker.distribution.manifest.v2+json\" 
			  $_repo_auth 
			  --head \"https://${_cfgstatus}/v2/${_image}/manifests/$_tag\""
			  
  fi
  
  _csum=$(eval $_tag_cmd | grep Docker-Content-Digest | awk -F' ' '{print $2}')
  
  echo "$_csum"
}

_error() {
  # Prefix die message with "cross mark (U+274C)", often displayed as a red x.
  printf "❌  "
  "${@}" 1>&2
}

_die() {
  # Prefix die message with "cross mark (U+274C)", often displayed as a red x.
  printf "❌  "
  "${@}" 1>&2
  exit 1
}

repo_path="$(mktemp -d)"
mkdir -p "$repo_path" >/dev/null

cd "$repo_path" 

git clone https://github.com/rancher/os-services.git &>/dev/null

cd os-services
git checkout "$BRANCH" &>/dev/null

echo "Switched to branch $BRANCH"

# cd /Users/ingemars/Projects/rancher-os-services

_list=($(grep -hr "image: rancher" ./ --include=*.yml | sed 's/image://g' | sed 's/ //g'))

for _img_line in "${_list[@]}"; do
	echo "Found image $_img_line"

	_docker_img="$(eval "echo $_img_line")"

	if [ $(echo "$_docker_img" | grep -c ":") -eq 0 ]; then
           _docker_img="$_docker_img:latest"
        fi
	
	_img_tag=$(echo "$_docker_img" | awk -F':' '{print $2}')
	_img_name_path=$(echo "$_docker_img" | awk -F':' '{print $1}')
	
	_img_name=$(echo "$_img_name_path" | awk -F'/' '{print $2}')
	
	_ntk_img_name="ros-${_img_name}"
	_ntk_img="repo.notakey.com/${_ntk_img_name}:${_img_tag}"

	_source_csum=$(_remote_tag_checksum "hub.docker.com" "$_img_name" "$_img_tag")
	_dest_csum=$(_remote_tag_checksum "$DEST_REPO" "$_ntk_img_name" "$_img_tag")
	
	echo "Source CSUM: $_source_csum"
	echo "Dest CSUM: $_dest_csum"
	
	if [ -z "$_source_csum" ]; then 
		_error echo "$_docker_img missing in source"
		continue
	fi
	
	if [ "$_dest_csum" = "$_source_csum" ]; then 
		echo "Image $_img_line up to date"
		continue
	fi

	echo -n "Pulling $_docker_img... "
	docker pull "$_docker_img" >/dev/null
	echo "done"
	
	echo -n "Tagging $_ntk_img... "
	docker tag "$_docker_img" "$_ntk_img" >/dev/null
	echo "done"

	echo -n "Pushing $_ntk_img... "
	docker push "$_ntk_img" >/dev/null
	echo "done"

	
	echo ""
	
done

rm -rf "$repo_path"
