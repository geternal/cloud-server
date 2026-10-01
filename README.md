# Ubuntu VMware Cloud Server

Build a VMware-importable `.ova` containing an official Ubuntu Server cloud image. On first boot, cloud-init creates your Linux user and enables password authentication for SSH.

## Build with GitHub Actions

1. In the repository, add an Actions secret named `VM_PASSWORD`. Use a strong password; the OVA contains its password hash and should be treated as sensitive.
2. Open **Actions** and run **Build VMware OVA**.
3. Choose `latest` for the newest supported Ubuntu LTS release, or enter a supported LTS version such as `24.04`. Set the Linux username.
4. Download the `ubuntu-vmware-ova` artifact from the completed workflow run.
5. Import the `.ova` in VMware Workstation, Fusion, or ESXi, then start the VM. The configured credentials are available after its first boot.

The build runs on GitHub-hosted Ubuntu and does not require VMware to be installed in the runner. The OVA is amd64 and includes a cloud-init seed ISO alongside the virtual disk.

## Build locally

On Ubuntu, install `cloud-image-utils`, `qemu-utils`, `jq`, `curl`, `openssl`, and `tar`, then run:

```sh
UBUNTU_VERSION=latest VM_USERNAME=serveradmin VM_PASSWORD='replace-me' bash scripts/build-ova.sh
```

Set `UBUNTU_VERSION` to a supported LTS version to select it explicitly. The output is written to `dist/` by default.