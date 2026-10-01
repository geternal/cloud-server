# Ubuntu VMware Cloud Server

Build a VMware-importable `.ova` containing an official Ubuntu Server cloud image. On first boot, cloud-init creates your Linux user and enables password authentication for SSH.

## Build with GitHub Actions

1. Open **Actions** and run **Build VMware OVA**.
2. Choose `latest` for the newest supported Ubuntu LTS release, or enter a supported LTS version such as `24.04`. Set the Linux username and password.
3. Download the `ubuntu-vmware-ova` artifact from the completed workflow run.
4. Import the `.ova` in VMware Workstation, Fusion, or ESXi, then start the VM. The configured credentials are available after its first boot.

The password input is a regular text field, not a masked secret. GitHub run details may expose it to people with access to the workflow run. Use a unique password, and prefer the `VM_PASSWORD` repository secret if run-history visibility is a concern. The OVA contains the password hash and should also be treated as sensitive.

The build runs on GitHub-hosted Ubuntu and does not require VMware to be installed in the runner. The OVA is amd64 and includes a cloud-init seed ISO alongside the virtual disk.

## Build locally

On Ubuntu, install `cloud-image-utils`, `qemu-utils`, `jq`, `curl`, `openssl`, and `tar`, then run:

```sh
UBUNTU_VERSION=latest VM_USERNAME=serveradmin VM_PASSWORD='replace-me' bash scripts/build-ova.sh
```

Set `UBUNTU_VERSION` to a supported LTS version to select it explicitly. The output is written to `dist/` by default.