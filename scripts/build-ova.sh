#!/usr/bin/env bash
set -euo pipefail

ubuntu_version=${UBUNTU_VERSION:-latest}
vm_username=${VM_USERNAME:-serveradmin}
vm_password=${VM_PASSWORD:-}
output_dir=${OUTPUT_DIR:-dist}

if [[ ! "$vm_username" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
  echo "VM_USERNAME must be a valid Linux username." >&2
  exit 1
fi
if [[ -z "$vm_password" ]]; then
  echo "VM_PASSWORD must be set." >&2
  exit 1
fi

for command in curl qemu-img cloud-localds openssl jq tar shasum; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Missing required command: $command" >&2
    exit 1
  fi
done

metadata=$(curl --fail --silent --show-error https://changelogs.ubuntu.com/meta-release-lts)
releases=$(printf '%s\n' "$metadata" | awk '
  /^Version: / { split($2, parts, "."); version = parts[1] "." parts[2] }
  /^Dist: / { codename = $2 }
  /^Supported: / { supported = $2 }
  /^$/ {
    if (supported == "1" && version ~ /^[0-9]+\.[0-9]+$/ && codename ~ /^[a-z]+$/) {
      print version, codename
    }
    version = codename = supported = ""
  }
  END {
    if (supported == "1" && version ~ /^[0-9]+\.[0-9]+$/ && codename ~ /^[a-z]+$/) {
      print version, codename
    }
  }
' | sort -V -k1,1)

if [[ "$ubuntu_version" == "latest" ]]; then
  release=$(printf '%s\n' "$releases" | tail -n 1)
else
  if [[ ! "$ubuntu_version" =~ ^[0-9]+\.[0-9]+$ ]]; then
    echo "UBUNTU_VERSION must be 'latest' or a version such as 24.04." >&2
    exit 1
  fi
  release=$(printf '%s\n' "$releases" | awk -v version="$ubuntu_version" '$1 == version { print; exit }')
fi

if [[ -z "$release" ]]; then
  echo "No supported Ubuntu LTS release found for '$ubuntu_version'." >&2
  exit 1
fi

read -r ubuntu_version codename <<< "$release"
image_url="https://cloud-images.ubuntu.com/releases/${codename}/release/ubuntu-${ubuntu_version}-server-cloudimg-amd64.img"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

echo "Downloading Ubuntu ${ubuntu_version} (${codename}) cloud image..."
curl --fail --location --silent --show-error "$image_url" --output "$work_dir/source.img"

salt=$(openssl rand -hex 8)
password_hash=$(printf '%s' "$vm_password" | openssl passwd -6 -salt "$salt" -stdin)
unset vm_password

cat > "$work_dir/user-data" <<EOF
#cloud-config
users:
  - name: ${vm_username}
    gecos: Ubuntu Server User
    groups: [adm, sudo]
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    passwd: '${password_hash}'
ssh_pwauth: true
chpasswd:
  expire: false
disable_root: true
EOF

cat > "$work_dir/meta-data" <<EOF
instance-id: ubuntu-vmware-${ubuntu_version}
local-hostname: ubuntu-server
EOF

mkdir -p "$output_dir"
output_dir=$(cd "$output_dir" && pwd)
ova_name="ubuntu-${ubuntu_version}-vmware-amd64.ova"

qemu-img convert -p -f qcow2 -O vmdk -o subformat=streamOptimized \
  "$work_dir/source.img" "$work_dir/disk.vmdk"
cloud-localds "$work_dir/seed.iso" "$work_dir/user-data" "$work_dir/meta-data"
disk_bytes=$(qemu-img info --output=json "$work_dir/disk.vmdk" | jq -r '.["virtual-size"]')

cat > "$work_dir/ubuntu-server.ovf" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<ovf:Envelope xmlns:ovf="http://schemas.dmtf.org/ovf/envelope/1" xmlns:rasd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_ResourceAllocationSettingData" xmlns:vssd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_VirtualSystemSettingData" xmlns:vmw="http://www.vmware.com/schema/ovf">
  <ovf:References>
    <ovf:File ovf:href="disk.vmdk" ovf:id="diskFile" ovf:size="$(stat -c '%s' "$work_dir/disk.vmdk")" />
    <ovf:File ovf:href="seed.iso" ovf:id="seedFile" ovf:size="$(stat -c '%s' "$work_dir/seed.iso")" />
  </ovf:References>
  <ovf:DiskSection>
    <ovf:Info>Virtual disks</ovf:Info>
    <ovf:Disk ovf:capacity="$disk_bytes" ovf:capacityAllocationUnits="byte * 2^0" ovf:diskId="systemDisk" ovf:fileRef="diskFile" ovf:format="http://www.vmware.com/interfaces/specifications/vmdk.html#streamOptimized" />
  </ovf:DiskSection>
  <ovf:NetworkSection>
    <ovf:Info>Logical networks</ovf:Info>
    <ovf:Network ovf:name="nat"><ovf:Description>VMware network; select a network during import.</ovf:Description></ovf:Network>
  </ovf:NetworkSection>
  <ovf:VirtualSystem ovf:id="ubuntu-server">
    <ovf:Info>Ubuntu cloud server</ovf:Info>
    <ovf:Name>Ubuntu ${ubuntu_version} Server</ovf:Name>
    <ovf:OperatingSystemSection ovf:id="94" vmw:osType="ubuntu64Guest">
      <ovf:Info>Guest operating system</ovf:Info>
      <ovf:Description>Ubuntu Linux (64-bit)</ovf:Description>
    </ovf:OperatingSystemSection>
    <ovf:VirtualHardwareSection>
      <ovf:Info>Virtual hardware requirements</ovf:Info>
      <ovf:System>
        <vssd:ElementName>Virtual Hardware Family</vssd:ElementName>
        <vssd:InstanceID>0</vssd:InstanceID>
        <vssd:VirtualSystemType>vmx-13</vssd:VirtualSystemType>
      </ovf:System>
      <ovf:Item>
        <rasd:ElementName>2 virtual CPUs</rasd:ElementName><rasd:InstanceID>1</rasd:InstanceID><rasd:ResourceType>3</rasd:ResourceType><rasd:VirtualQuantity>2</rasd:VirtualQuantity>
      </ovf:Item>
      <ovf:Item>
        <rasd:AllocationUnits>byte * 2^20</rasd:AllocationUnits><rasd:ElementName>4096 MB of memory</rasd:ElementName><rasd:InstanceID>2</rasd:InstanceID><rasd:ResourceType>4</rasd:ResourceType><rasd:VirtualQuantity>4096</rasd:VirtualQuantity>
      </ovf:Item>
      <ovf:Item>
        <rasd:Address>0</rasd:Address><rasd:ElementName>SCSI controller 0</rasd:ElementName><rasd:InstanceID>3</rasd:InstanceID><rasd:ResourceSubType>lsilogic</rasd:ResourceSubType><rasd:ResourceType>6</rasd:ResourceType>
      </ovf:Item>
      <ovf:Item>
        <rasd:AddressOnParent>0</rasd:AddressOnParent><rasd:ElementName>Hard disk 1</rasd:ElementName><rasd:HostResource>ovf:/disk/systemDisk</rasd:HostResource><rasd:InstanceID>4</rasd:InstanceID><rasd:Parent>3</rasd:Parent><rasd:ResourceType>17</rasd:ResourceType>
      </ovf:Item>
      <ovf:Item>
        <rasd:AddressOnParent>1</rasd:AddressOnParent><rasd:AutomaticAllocation>true</rasd:AutomaticAllocation><rasd:ElementName>Cloud-init seed</rasd:ElementName><rasd:HostResource>ovf:/file/seedFile</rasd:HostResource><rasd:InstanceID>5</rasd:InstanceID><rasd:Parent>3</rasd:Parent><rasd:ResourceSubType>vmware.cdrom.iso</rasd:ResourceSubType><rasd:ResourceType>15</rasd:ResourceType>
      </ovf:Item>
      <ovf:Item>
        <rasd:AddressOnParent>7</rasd:AddressOnParent><rasd:Connection>nat</rasd:Connection><rasd:ElementName>Network adapter 1</rasd:ElementName><rasd:InstanceID>6</rasd:InstanceID><rasd:ResourceSubType>e1000e</rasd:ResourceSubType><rasd:ResourceType>10</rasd:ResourceType>
      </ovf:Item>
    </ovf:VirtualHardwareSection>
  </ovf:VirtualSystem>
</ovf:Envelope>
EOF

cd "$work_dir"
for file in ubuntu-server.ovf disk.vmdk seed.iso; do
  digest=$(openssl dgst -sha1 "$file" | awk '{print $NF}')
  printf 'SHA1(%s)= %s\n' "$file" "$digest"
done > ubuntu-server.mf

tar --format=ustar -cf "$output_dir/$ova_name" ubuntu-server.ovf disk.vmdk seed.iso ubuntu-server.mf
echo "Created $output_dir/$ova_name"