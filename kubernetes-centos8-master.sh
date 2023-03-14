#!/bin/bash
echo Kubemaster Hostname:
read hostname
echo Kubernetes Admin Account:
read adminaccount
echo Kubernetes Admin Password:
read adminpassword
#hostname="kubemaster"
ip=$(/sbin/ip -o -4 addr list ens192 | awk '{print $4}' | cut -d/ -f1)
hostnamectl set-hostname $hostname
sed -i -e '1i'$ip'   '$hostname'\' /etc/hosts
cd /etc/yum.repos.d/
sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-*
sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
enabled=1
gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl
EOF
yum update -y
wait
setenforce 0
sed -i --follow-symlinks 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux
firewall-cmd --add-masquerade --permanent
firewall-cmd --reload
systemctl stop firewalld
systemctl disable firewalld
cd /root
cat << EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sysctl --system
sysctl -p /etc/sysctl.d/k8s.conf
sudo swapoff -a
modprobe overlay
modprobe br_netfilter
curl -LO https://github.com/containerd/containerd/releases/download/v1.6.16/containerd-1.6.16-linux-amd64.tar.gz
wait
tar Cxzvf /usr/local containerd-1.6.16-linux-amd64.tar.gz
cat << EOF | sudo tee /etc/systemd/system/containerd.service
[Unit]
Description=containerd
Documentation=https://containerd.io

[Service]
Type=notify
ExecStart=/usr/local/bin/containerd

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl enable containerd
sudo systemctl start containerd
curl -LO https://github.com/opencontainers/runc/releases/download/v1.1.4/runc.amd64
wait
install -m 755 runc.amd64 /usr/local/sbin/runc
mkdir -p /opt/cni/bin
curl -LO https://github.com/containernetworking/plugins/releases/download/v1.2.0/cni-plugins-linux-amd64-v1.2.0.tgz
wait
tar Cxzvf /opt/cni/bin cni-plugins-linux-amd64-v1.2.0.tgz 
adduser $adminaccount
echo "$adminpassword" | sudo passwd $adminaccount --stdin
sed -i 's/^#\s*\(%wheel\s\+ALL=(ALL)\s\+NOPASSWD:\s\+ALL\)/\1/' /etc/sudoers
sudo usermod -aG wheel $adminaccount
sudo yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
wait
sudo systemctl enable --now kubelet
sudo kubeadm init  --apiserver-advertise-address=10.201.53.70 --pod-network-cidr=192.168.0.0/16
wait
mkdir -p /home/$adminaccount/.kube
sudo cp -i /etc/kubernetes/admin.conf /home/$adminaccount/.kube/config
sudo chown $adminaccount:$adminaccount /home/$adminaccount/.kube/
sudo chown $adminaccount:$adminaccount /home/$adminaccount/.kube/config
wait
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/tigera-operator.yaml
wait
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/custom-resources.yaml
wait
kubeadm token create --print-join-command
cd /home/$adminaccount/
echo Kubernetes Master node Installation Success! copy the token and paste on the worker nodes
su $adminaccount
