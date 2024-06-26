FROM ubuntu

RUN apt update
RUN apt -y install ssh curl jq libdigest-sha-perl dnsutils vim gnupg software-properties-common
RUN wget https://get.helm.sh/helm-v3.13.1-linux-amd64.tar.gz; tar xvf helm-v3.13.1-linux-amd64.tar.gz; install linux-amd64/helm /usr/local/bin/helm; rm -rf linux-amd64/; rm -rf helm-v3.13.1-linux-amd64.tar.gz
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"; install kubectl /usr/local/bin/kubectl; rm -rf kubectl
RUN wget -O- https://carvel.dev/install.sh > install.sh
RUN bash install.sh; rm install.sh
RUN wget https://github.com/mikefarah/yq/releases/download/v4.30.1/yq_linux_amd64
RUN install yq_linux_amd64 /usr/local/bin/yq; rm yq_linux_amd64
RUN curl -sfL https://get.hauler.dev | sed 's/sudo//g' | HAULER_VERSION=1.0.3 bash
RUN wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
RUN gpg --no-default-keyring --keyring /usr/share/keyrings/hashicorp-archive-keyring.gpg --fingerprint
RUN echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list
RUN apt update; apt -y install terraform
RUN wget -O- https://github.com/kubernetes-sigs/cluster-api/releases/download/v1.7.3/clusterctl-linux-amd64 > /tmp/clusterctl
RUN install /tmp/clusterctl /usr/local/bin/clusterctl

RUN mkdir -p /data