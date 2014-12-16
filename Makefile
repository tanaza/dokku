DOKKU_VERSION = master

SSHCOMMAND_URL ?= https://raw.github.com/progrium/sshcommand/master/sshcommand
PLUGINHOOK_URL ?= https://s3.amazonaws.com/progrium-pluginhook/pluginhook_0.1.0_amd64.deb
STACK_URL ?= https://github.com/progrium/buildstep.git
PREBUILT_STACK_URL ?= https://github.com/progrium/buildstep/releases/download/2014-03-08/2014-03-08_429d4a9deb.tar.gz
DOKKU_ROOT ?= /home/dokku
PLUGIN_PATH ?= /var/lib/dokku/plugins

# If the first argument is "vagrant-dokku"...
ifeq (vagrant-dokku,$(firstword $(MAKECMDGOALS)))
  # use the rest as arguments for "vagrant-dokku"
  RUN_ARGS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
  # ...and turn them into do-nothing targets
  $(eval $(RUN_ARGS):;@:)
endif

.PHONY: all install copyfiles version plugins dependencies sshcommand pluginhook docker aufs stack count dokku-installer vagrant-acl-add vagrant-dokku

all:
	# Type "make install" to install.

install: dependencies stack copyfiles plugin-dependencies plugins version

copyfiles: addman
	cp dokku /usr/local/bin/dokku
	mkdir -p ${PLUGIN_PATH}
	find ${PLUGIN_PATH} -mindepth 2 -maxdepth 2 -name '.core' -printf '%h\0' | xargs -0 rm -Rf
	find plugins/ -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | while read plugin; do \
	    rm -Rf ${PLUGIN_PATH}/$$plugin && \
	    cp -R plugins/$$plugin ${PLUGIN_PATH} && \
	    touch ${PLUGIN_PATH}/$$plugin/.core; \
	    done

addman:
	mkdir -p /usr/local/share/man/man1
	cp dokku.1 /usr/local/share/man/man1/dokku.1
	mandb

version:
	git describe --tags > ${DOKKU_ROOT}/VERSION  2> /dev/null || echo '~${DOKKU_VERSION} ($(shell date -uIminutes))' > ${DOKKU_ROOT}/VERSION

plugin-dependencies: pluginhook
	DOKKU_TRACE=1 dokku plugins-install-dependencies

plugins: pluginhook docker
	DOKKU_TRACE=1 dokku plugins-install

dependencies: sshcommand pluginhook docker stack

sshcommand:
	wget -qO /usr/local/bin/sshcommand ${SSHCOMMAND_URL}
	chmod +x /usr/local/bin/sshcommand
	sshcommand create dokku /usr/local/bin/dokku

pluginhook:
	wget -qO /tmp/pluginhook_0.1.0_amd64.deb ${PLUGINHOOK_URL}
	dpkg -i /tmp/pluginhook_0.1.0_amd64.deb

docker: aufs
	apt-get install -qq -y curl
	egrep -i "^docker" /etc/group || groupadd docker
	usermod -aG docker dokku
	curl --silent https://get.docker.io/gpg | apt-key add -
	echo deb http://get.docker.io/ubuntu docker main > /etc/apt/sources.list.d/docker.list
	apt-get update
ifdef DOCKER_VERSION
	apt-get install -qq -y lxc-docker-${DOCKER_VERSION}
else
	apt-get install -qq -y lxc-docker
endif
	sleep 2 # give docker a moment i guess

aufs:
	lsmod | grep aufs || modprobe aufs || apt-get install -qq -y linux-image-extra-`uname -r` > /dev/null

stack:
	@echo "Start building buildstep"
ifdef BUILD_STACK
	@docker images | grep progrium/buildstep || (git clone ${STACK_URL} /tmp/buildstep && docker build -t progrium/buildstep /tmp/buildstep && rm -rf /tmp/buildstep)
else
	@docker images | grep progrium/buildstep || curl --silent -L ${PREBUILT_STACK_URL} | gunzip -cd | docker import - progrium/buildstep
endif

count:
	@echo "Core lines:"
	@cat dokku bootstrap.sh | wc -l
	@echo "Plugin lines:"
	@find plugins -type f | xargs cat | wc -l
	@echo "Test lines:"
	@find tests -type f | xargs cat | wc -l

dokku-installer:
	apt-get install -qq -y ruby
	test -f /var/lib/dokku/.dokku-installer-created || gem install rack -v 1.5.2 --no-rdoc --no-ri
	test -f /var/lib/dokku/.dokku-installer-created || gem install rack-protection -v 1.5.3 --no-rdoc --no-ri
	test -f /var/lib/dokku/.dokku-installer-created || gem install sinatra -v 1.4.5 --no-rdoc --no-ri
	test -f /var/lib/dokku/.dokku-installer-created || gem install tilt -v 1.4.1 --no-rdoc --no-ri
	test -f /var/lib/dokku/.dokku-installer-created || ruby /root/dokku/contrib/dokku-installer.rb onboot
	test -f /var/lib/dokku/.dokku-installer-created || service dokku-installer start
	test -f /var/lib/dokku/.dokku-installer-created || service nginx reload
	test -f /var/lib/dokku/.dokku-installer-created || touch /var/lib/dokku/.dokku-installer-created

vagrant-acl-add:
	vagrant ssh -- sudo sshcommand acl-add dokku $(USER)

vagrant-dokku:
	vagrant ssh -- "sudo -H -u root bash -c 'dokku $(RUN_ARGS)'"
