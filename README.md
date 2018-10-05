# rundeck-toolbox
Multiple tools related to Rundeck (backup, monitoring, ...)


# Maintenance tools
###### rundeck_backup.sh
Tool for creating a rundeck backup.  
Requires [rundeck-cli](https://github.com/rundeck/rundeck-cli) (and a Rundeck API token).  
The following elements will be collected and stored in a tar.gz archive :
- Rundeck project definitions
- Rundeck job definitions (failsafe)
- Rundeck project data on local FS (failsafe)
- Rundeck $HOME/.ssh directory
- Rundeck local tool directory

The archive will also collect a txt file listing the location or usage of each elements.

**Usage** : `rundeck_backup.sh -backup_dir <target backup directory>`  
Adjust the variable at start for the username or the tool directory location.

###### rundeck_history_clear.sh
Tool for some cleanup operation on Rundeck execution history. Run from Rundeck.
Requires a Rundeck API token stored in the environment variable `RD_TOKEN=<api token>`  

Comes with a self-help, but should be used like is :  
**Daily usage**: `rundeck_history_clear.sh -clear jobs -state succeeded -keep_count 5`  
This command will, for each job, keep the 5 most recent executions and clear all the oldest with a successed state.

**Weekly usage**: `rundeck_history_clear.sh -clear projects -state all -older 3m`  
This command will clear all execution history (any status) older than 3 months for each project.


# Monitoring tools
The java JMX-HTTP bridge [Jolokia](https://jolokia.org/) is not listed but required.  
The jolokia-jvm-agent.jar module is inserted in the java process through the RDECK_JVM_SETTINGS config variable.  
Just add this line (adjust the path) and restart:  
`-javaagent:/server/jolokia/jolokia/jolokia-jvm-agent.jar=port=34440,host=localhost`  
It'll open an http access to the JMX informations in the Rundeck JVM, readable by curl, for example.  

###### ansible-group_vars/app_name
Variable definition template for any Ansible inventory JVM group.
Used by the Telegraf JVM conf template.

###### ansible-telegraf_templates/java_jvm-all.conf.j2
Ansible template able to create a generic configuration for the [Influxdata/Telegraf](https://github.com/influxdata/telegraf) agent.  
The idea is to loop on any group listed in the Ansible inventory for the current node, and search for variables named \<group name\>_jvm.  
Then, repeat the java_jvm template for each existing JVM.  
*If you don't need it or don't use Ansible, just clear / replace the ansible variables and the template is ready to be used by Telegraf.*

###### ansible-telegraf_templates/rundeck.conf.j2
Ansible template for Telegraf, to call rundeck_job_status and collect the data.  
Uses 3 Ansible variables : rundeck_server, rundeck_port, rundeck_monitoring_token.  
Just replace the values if you don't need it.  

###### rundeck_job_status.sh
Calls the Rundeck API to return the job execution status and count for each project. 
Requires an API Token, as usual.  
Self-help available.

