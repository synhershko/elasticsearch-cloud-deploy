# Required variables
# - aws_region
# - es_environment
# - masters_count

while true
do
    echo "Fetching masters..."
    MASTER_INSTANCES="$(aws ec2 describe-instances --region=$aws_region --filters Name=instance-state-name,Values=running Name=tag:Role,Values=master Name=tag:Cluster,Values=$es_environment | jq -r '.Reservations | map(.Instances[].InstanceId) | .[]' | sort)"
    COUNT=`echo "$MASTER_INSTANCES" | wc -l`

    if [ "$COUNT" -eq "$masters_count" ]; then
        echo "Masters count is correct... Rechecking in 60 sec"
        sleep 60
        MASTER_INSTANCES_RECHECK="$(aws ec2 describe-instances --region=$aws_region --filters Name=instance-state-name,Values=running Name=tag:Role,Values=master Name=tag:Cluster,Values=$es_environment | jq -r '.Reservations | map(.Instances[].InstanceId) | .[]' | sort)"
    
        if [ "$MASTER_INSTANCES" = "$MASTER_INSTANCES_RECHECK" ]; then
            break
        fi
    fi

    sleep 5
done

echo "Fetched masters"
MASTER_IPS="$(aws ec2 describe-instances --region $aws_region --instance-ids $MASTER_INSTANCES | jq -r '.Reservations[].Instances[].PrivateIpAddress')"
SEED_HOSTS=`echo "$MASTER_IPS" | paste -sd ',' -`
INITIAL_MASTER_NODES=`echo "$MASTER_IPS" | awk '{print "ip-" $0}' | tr . - | paste -sd ',' -`

echo "discovery.seed_hosts: $SEED_HOSTS" >>/etc/elasticsearch/elasticsearch.yml
echo "cluster.initial_master_nodes: $(hostname),$INITIAL_MASTER_NODES" >>/etc/elasticsearch/elasticsearch.yml
