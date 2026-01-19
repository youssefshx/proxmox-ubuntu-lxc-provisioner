# Proxmox Ubuntu LXC Provisioner

A production-style Ansible automation package to manage the **full LXC lifecycle on Proxmox VE**:

- **Download Ubuntu LXC templates** to Proxmox storage
- **Provision Ubuntu LXC containers** from a declarative YAML “container map”
- **Nuke (stop + destroy)** containers defined in a container map
- Generate a **ready-to-copy Ansible deployment scaffold** (inventory, `ansible.cfg`, starter playbook, and a single keypair) under `output/<deployment-name>/`

This repository is intended for public publication. Environment-specific settings should live in local, ignored files created from the provided `.example` templates.

---

## Table of contents

- [What you get](#what-you-get)
- [Security posture](#security-posture)
- [Repository layout](#repository-layout)
- [Public-safe configuration model](#public-safe-configuration-model)
- [Quickstart](#quickstart)
  - [Native Linux](#native-linux)
  - [Windows + WSL via PowerShell one-liners](#windows--wsl-via-powershell-one-liners)
- [Playbooks](#playbooks)
  - [`playbooks/download-templates.yml`](#playbooksdownload-templatesyml)
  - [`playbooks/provision.yml`](#playbooksprovisionyml)
  - [`playbooks/nuke-provision.yml`](#playbooksnuke-provisionyml)
- [Container map (YAML) reference](#container-map-yaml-reference)
  - [Top-level keys](#top-level-keys)
  - [`lxc_defaults`](#lxc_defaults)
  - [`lxc_containers[]`](#lxc_containers)
  - [Provision types](#provision-types)
  - [Storage backends](#storage-backends)
  - [Networking (bridge, VLANs, DNS)](#networking-bridge-vlans-dns)
  - [Mounts (bind mounts)](#mounts-bind-mounts)
- [Generated deployment scaffold](#generated-deployment-scaffold)
- [Operations & safety notes](#operations--safety-notes)
- [Troubleshooting](#troubleshooting)
- [Publishing checklist](#publishing-checklist)

---

## What you get

When you run the provisioner against a container map, it:

1. Validates Proxmox prerequisites on each target host
2. Creates containers (idempotent if they already exist)
3. Applies an LXC security profile (`unprivileged`, `privileged`, `nvidia_gpu`)
4. Bootstraps the OS (packages, SSH hardening, firewall, updates, etc.)
5. Creates an `ansible` user and installs your deployment public key
6. Generates a complete Ansible project in `output/<deployment-name>/`

The deployment name is derived from the map filename:
- `examples/my-deployment.yml` → `output/my-deployment/`
- keypair name: `output/my-deployment/my-deployment.pem`

---

## Security posture

This automation applies a baseline hardening profile inside each container:

- **SSH key-only authentication**
  - Disables `PasswordAuthentication`
  - Disables PAM/challenge-response where applicable
- **Firewall enabled by default**
  - UFW allows **SSH (22/tcp)** + **ICMP** only by default
- **Telemetry/bloatware disabled**
- **Automatic security updates enabled**
- **Consistent management access**
  - An `ansible` user is created
  - Password is removed/locked (key-only access)
  - `ansible` has passwordless sudo (for automation)

If your application requires additional ports (e.g., OpenSearch `9200/9300`, web `80/443`, etc.), open them after provisioning via Ansible or manual change control.

---

## Repository layout

```
proxmox_ubuntu_lxc_provisioner/
├── inventories/
│   ├── hosts.ini                 # Your Proxmox hosts (private; ignored)
│   ├── hosts.ini.example         # Template (tracked)
│   └── group_vars/
│       ├── all.yml               # Your defaults (private; ignored)
│       ├── all.yml.example       # Template (tracked)
│       ├── proxmox_hosts.yml     # Proxmox host group vars (private; ignored)
│       └── proxmox_hosts.yml.example
├── playbooks/
│   ├── download-templates.yml
│   ├── provision.yml
│   └── nuke-provision.yml
├── examples/
│   ├── template.yml
│   ├── test-minimal.yml
│   ├── test-suite.yml
│   └── <your deployments>.yml
└── output/                       # Generated per-deployment Ansible projects (ignored)
```

---

## Public-safe configuration model

The tracked repo provides `.example` templates. You create your real configs locally:

```bash
cp inventories/hosts.ini.example inventories/hosts.ini
cp inventories/group_vars/all.yml.example inventories/group_vars/all.yml
cp inventories/group_vars/proxmox_hosts.yml.example inventories/group_vars/proxmox_hosts.yml
```

The following are expected to be ignored by `.gitignore`:
- `inventories/hosts.ini`
- `inventories/group_vars/all.yml`
- `inventories/group_vars/proxmox_hosts.yml`
- `output/`
- `*.pem` / SSH private keys

This keeps your host IPs and infrastructure naming private while letting you publish the automation publicly.

---

## Quickstart

### Native Linux

#### 1) Install Ansible

Ubuntu/Debian:

```bash
sudo apt update
sudo apt install -y ansible
```

#### 2) Configure inventory and vars

```bash
cp inventories/hosts.ini.example inventories/hosts.ini
cp inventories/group_vars/all.yml.example inventories/group_vars/all.yml
cp inventories/group_vars/proxmox_hosts.yml.example inventories/group_vars/proxmox_hosts.yml
```

Edit:
- `inventories/hosts.ini` (your Proxmox hosts)
- `inventories/group_vars/all.yml` (template storage defaults, optional settings)
- `inventories/group_vars/proxmox_hosts.yml` (sysctls, kernel modules, etc.)

Connectivity check:

```bash
ansible -i inventories/hosts.ini proxmox_hosts -m ping
```

#### 3) Download templates (recommended)

```bash
ansible-playbook -i inventories/hosts.ini playbooks/download-templates.yml
```

#### 4) Provision a test container

```bash
ansible-playbook -i inventories/hosts.ini playbooks/provision.yml \
  -e lxc_map_file=examples/test-minimal.yml
```

#### 5) Use the generated scaffold

```bash
cd output/test-minimal
ansible all -m ping
ansible-playbook playbooks/site.yml
```

---

### Windows + WSL via PowerShell one-liners

This repo is designed to run Ansible inside WSL. The commands below are the “single-line” PowerShell → WSL pattern.

> Adjust the repo path to your environment.

#### Connectivity check

```powershell
wsl -e bash -lc "cd /mnt/c/Users/Public/Dev/<repo-path>/proxmox_ubuntu_lxc_provisioner && ansible -i inventories/hosts.ini proxmox_hosts -m ping"
```

#### Download templates

```powershell
wsl -e bash -lc "cd /mnt/c/Users/Public/Dev/<repo-path>/proxmox_ubuntu_lxc_provisioner && ansible-playbook -i inventories/hosts.ini playbooks/download-templates.yml"
```

Download only Ubuntu 24.04:

```powershell
wsl -e bash -lc "cd /mnt/c/Users/Public/Dev/<repo-path>/proxmox_ubuntu_lxc_provisioner && ansible-playbook -i inventories/hosts.ini playbooks/download-templates.yml -e ""template_versions=['24.04']"""
```

Download to a different storage backend:

```powershell
wsl -e bash -lc "cd /mnt/c/Users/Public/Dev/<repo-path>/proxmox_ubuntu_lxc_provisioner && ansible-playbook -i inventories/hosts.ini playbooks/download-templates.yml -e template_storage=local"
```

#### Provision a deployment

```powershell
wsl -e bash -lc "cd /mnt/c/Users/Public/Dev/<repo-path>/proxmox_ubuntu_lxc_provisioner && ansible-playbook -i inventories/hosts.ini playbooks/provision.yml -e lxc_map_file=examples/test-minimal.yml"
```

#### Nuke (destroy) a deployment

```powershell
wsl -e bash -lc "cd /mnt/c/Users/Public/Dev/<repo-path>/proxmox_ubuntu_lxc_provisioner && ansible-playbook -i inventories/hosts.ini playbooks/nuke-provision.yml -e lxc_map_file=examples/test-minimal.yml -e skip_confirmation=true"
```

#### WSL/NTFS SSH key permissions (important)

If you try to SSH using a key stored under `/mnt/c/...`, OpenSSH may reject it:

- `WARNING: UNPROTECTED PRIVATE KEY FILE!`
- `bad permissions`

Fast workaround:

```bash
cp output/<deployment>/<deployment>.pem /tmp/
chmod 600 /tmp/<deployment>.pem
ssh -i /tmp/<deployment>.pem ansible@<container_ip>
```

Best practice:
- run the deployment scaffold from a WSL filesystem path (e.g., copy `output/<deployment>` into `~/deployments/<deployment>`)

---

## Playbooks

### `playbooks/download-templates.yml`

**Goal:** Download Ubuntu LXC templates to a Proxmox storage backend.

**Default behavior:**
- Downloads versions `22.04`, `24.04`, `25.04`
- Targets a storage defined by `template_storage` (defaults to group vars if present)

**Key variables:**
- `template_storage` (string): Proxmox storage ID (e.g., `local`, `nfs-templates`, `ceph-templates`)
- `template_versions` (list): versions to download, e.g. `['24.04']`

**Examples:**

Download all default versions:

```bash
ansible-playbook -i inventories/hosts.ini playbooks/download-templates.yml
```

Download only `24.04`:

```bash
ansible-playbook -i inventories/hosts.ini playbooks/download-templates.yml \
  -e "template_versions=['24.04']"
```

Download to a different storage backend:

```bash
ansible-playbook -i inventories/hosts.ini playbooks/download-templates.yml \
  -e template_storage=local
```

**Operational notes:**
- Verifies storage exists via `pvesm status`
- Creates template directory if needed
- Skips already-present templates
- Uses retries for robustness

---

### `playbooks/provision.yml`

**Goal:** Create and configure containers from a map file.

**Required input:**
- `lxc_map_file` (path): the container map YAML

Example:

```bash
ansible-playbook -i inventories/hosts.ini playbooks/provision.yml \
  -e lxc_map_file=examples/my-deployment.yml
```

**What it does (high-level flow):**
1. Load the container map
2. Validate host prerequisites (storage, kernel modules, sysctls)
3. (If relevant) detect NVIDIA devices/driver on Proxmox hosts
4. Generate a single **deployment SSH keypair**
5. Create containers (only if missing)
6. Apply LXC security profile by provision type
7. Start containers and wait for readiness
8. Bootstrap OS and security inside container
9. Create `ansible` user and install authorized key
10. Generate the **deployment scaffold** in `output/<deployment-name>/`

---

### `playbooks/nuke-provision.yml`

**Goal:** Stop and destroy all containers defined in a map file.

Example:

```bash
ansible-playbook -i inventories/hosts.ini playbooks/nuke-provision.yml \
  -e lxc_map_file=examples/my-deployment.yml
```

**Options:**
- `skip_confirmation=true` (bool): disables interactive confirmation
- `keep_output=true` (bool): keeps `output/<deployment-name>/` while destroying containers

Non-interactive:

```bash
ansible-playbook -i inventories/hosts.ini playbooks/nuke-provision.yml \
  -e lxc_map_file=examples/my-deployment.yml \
  -e skip_confirmation=true
```

---

## Container map (YAML) reference

### Top-level keys

- `lxc_defaults:` (object) — defaults for all containers
- `lxc_containers:` (list) — container definitions
- `nvidia:` (optional) — driver version for `nvidia_gpu` deployments

---

### `lxc_defaults`

Common defaults:

- `template` (string): `storage:vztmpl/<template-file>`
- `bridge` (string): e.g. `vmbr0`
- `vlan_tag` (int): e.g. `0` (untagged) or `22`
- `gateway` (string): default gateway
- `dns` (string): resolver IP
- `memory` (int): MB
- `cores` (int): CPU cores

Example:

```yaml
lxc_defaults:
  template: "nfs-templates:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
  bridge: vmbr0
  vlan_tag: 0
  gateway: 10.0.0.1
  dns: "10.0.0.1"
  memory: 2048
  cores: 2
```

---

### `lxc_containers[]`

Per-container fields:

Required:
- `id` (int): Proxmox VMID
- `host` (string): Proxmox host IP/name (must match `inventory_hostname`)
- `hostname` (string)
- `ip` (string): CIDR format
- `rootfs` (string): e.g. `local-lvm:20`, `rbd-pool:100`, `zfs-pool:500`

Optional (override defaults):
- `provision_type`: `unprivileged` | `privileged` | `nvidia_gpu`
- `memory`, `cores`
- `bridge`, `vlan_tag`, `gateway`, `dns`
- `mounts` (list)

Example:

```yaml
- id: 2001
  host: 192.168.10.11
  hostname: app-001
  ip: 10.0.50.11/24
  provision_type: unprivileged
  rootfs: local-lvm:40
```

---

### Provision types

- `unprivileged`
  - best default for most services
  - reduced device access (strong isolation)

- `privileged`
  - device access enabled (useful for Docker, system workloads)

- `nvidia_gpu`
  - privileged + GPU passthrough + in-container driver install
  - requires NVIDIA driver installed on the Proxmox host
  - expects `nvidia-smi` functional on the host

---

### Storage backends

The playbook validates storage existence using `pvesm status` on each Proxmox host.

Common real-world backend examples:

- **Local LVM**: `local-lvm:20`
- **Ceph RBD**: `rbd-pool:200`
- **ZFS pool**: `zfs-pool:500`
- **NFS storage**: `nfs-data:1000`

Example (mixed storage):

```yaml
lxc_containers:
  - id: 3001
    host: 192.168.10.11
    hostname: web-001
    ip: 10.0.60.11/24
    rootfs: local-lvm:30

  - id: 3002
    host: 192.168.10.12
    hostname: db-001
    ip: 10.0.60.12/24
    rootfs: zfs-pool:500

  - id: 3003
    host: 192.168.10.13
    hostname: analytics-001
    ip: 10.0.60.13/24
    rootfs: rbd-pool:1000
```

> Always confirm the storage exists on the target host(s). A storage backend can be present on one host and absent on another.

---

### Networking (bridge, VLANs, DNS)

Supported configuration points:

- `bridge`: Proxmox bridge (`vmbr0`, `vmbr1`, etc.)
- `ip`: `X.X.X.X/YY`
- `gateway`: gateway on that subnet
- `dns`: resolver IP(s) as string
- `vlan_tag`: VLAN ID (`0` = untagged)

#### VLAN example

```yaml
lxc_defaults:
  bridge: vmbr0
  vlan_tag: 22
  gateway: 10.22.0.1
  dns: "10.22.0.1"

lxc_containers:
  - id: 4001
    host: 192.168.10.11
    hostname: vlan22-node
    ip: 10.22.90.10/24
    vlan_tag: 22
    rootfs: local-lvm:20
```

---

### Mounts (bind mounts)

Mount entries support directory bind mounts. Typical fields:

- `type: directory`
- `host_path`
- `container_path`
- `options` (optional), e.g. `",ro=1"`

Example:

```yaml
mounts:
  - type: directory
    host_path: /mnt/nfs/shared
    container_path: /mnt/shared

  - type: directory
    host_path: /mnt/nfs/readonly
    container_path: /mnt/readonly
    options: ",ro=1"
```

---

## Generated deployment scaffold

After provisioning `examples/my-deployment.yml`, you receive:

```
output/my-deployment/
├── my-deployment.pem
├── my-deployment.pem.pub
├── ansible.cfg
├── .gitignore
├── README.md
├── inventory/
│   ├── hosts.ini
│   └── group_vars/
│       └── all.yml
└── playbooks/
    └── site.yml
```

This folder is designed to be copied into a brand-new repo as the “runtime” management project for that deployment.

Typical usage:

```bash
cd output/my-deployment
ansible all -m ping
ansible-playbook playbooks/site.yml
```

---

## Operations & safety notes

- **Idempotency:** The provisioner is designed to be re-runnable. Existing containers should not be recreated.
- **Large rootfs sizes:** Large disks (e.g., multi-TB on `local-lvm`) can take time to allocate depending on thinpool behavior.
- **Firewall defaults:** Only SSH+ICMP are allowed initially. Plan required ports for your app after provisioning.
- **GPU containers:** Ensure the Proxmox host’s NVIDIA stack is working before using `nvidia_gpu`.

---

## Troubleshooting

### Ansible “world writable directory” warning (WSL)

If you run from `/mnt/c`, Ansible may ignore local `ansible.cfg`. This is a known behavior for world-writable directories under WSL/NTFS.

Mitigations:
- Run from WSL filesystem (`~/repos/...`)
- Or always pass `-i inventories/hosts.ini` explicitly (recommended)

### SSH key rejected due to permissions (WSL + /mnt/c)

Fix by copying the key to a Linux path and chmod:

```bash
cp output/<deployment>/<deployment>.pem /tmp/
chmod 600 /tmp/<deployment>.pem
ssh -i /tmp/<deployment>.pem ansible@<container_ip>
```

### Template not found

On Proxmox:

```bash
pveam update
pveam available | grep ubuntu
pveam list <storage-id>
```

Download missing template via playbook or `pveam download`.

### Storage errors

On Proxmox host:

```bash
pvesm status
```

Confirm the `rootfs:` storage backend exists on the host(s) you are targeting.

### Container won’t start

On the Proxmox host that owns the container:

```bash
pct status <id>
journalctl -u pve-container@<id> --no-pager | tail -200
cat /etc/pve/nodes/$(hostname)/lxc/<id>.conf
```

---

## Publishing checklist

Before publishing publicly:

1. Ensure private config files are ignored:
   - `inventories/hosts.ini`
   - `inventories/group_vars/all.yml`
   - `inventories/group_vars/proxmox_hosts.yml`
2. Ensure generated output is ignored:
   - `output/`
   - `*.pem`
3. Ensure only `.example` templates are committed for inventories/group_vars.
4. Decide and add a license if you want explicit licensing.
   - This repository currently does **not** include a `LICENSE` file.