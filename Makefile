
create:
	bash $(CURDIR)/utils/copy-templates.sh
	bash $(CURDIR)/create-ec2-swarm-cluster.sh
remove:
	bash $(CURDIR)/delete-ec2-swarm-cluster.sh
clean:
	rm -rf $(CURDIR)/password.properties
	rm -rf $(CURDIR)/aws-variables.properties
.PHONY: create remove clean