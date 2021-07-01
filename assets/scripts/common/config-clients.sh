# Required variables
# - client_user
# - client_pwd
# - security_enabled
# - monitoring_enabled
# - BIND_TO_ALL
# - ES_HOST
# - CURL_AUTH


function setup_grafana_dashboard() {
    GRAFANA_BASIC_AUTH=""
    if [ "$security_enabled" == "true" ]; then
        GRAFANA_BASIC_AUTH=" --user $client_user:$client_pwd "
    fi

    while true; do
        echo "Waiting for grafana to become available..."
        if curl $GRAFANA_BASIC_AUTH --output /dev/null --fail http://localhost:3000; then break; fi
        sleep 5
    done

    cat <<EOF >>/tmp/grafana-datasource.json
{
    "name": "Elasticsearch Monitor",
    "type": "elasticsearch",
    "typeLogoUrl": "public/app/plugins/datasource/elasticsearch/img/elasticsearch.svg",
    "access": "proxy",
    "url": "$ES_HOST",
    "password": "",
    "user": "",
    "database": "[.monitoring-es-*-]YYYY.MM.DD",
    "isDefault": true,
    "jsonData": {
      "esVersion": 70,
      "interval": "Daily",
      "logLevelField": "",
      "logMessageField": "",
      "maxConcurrentShardRequests": 5,
      "timeField": "timestamp"
    },
    "readOnly": false,
EOF

    if [ "$security_enabled" == "true" ]; then
        cat <<EOF >>/tmp/grafana-datasource.json
    "basicAuth": true,
    "basicAuthUser": "$client_user",
    "secureJsonData": { "basicAuthPassword": "$client_pwd" }
}
EOF
    else
        echo '"basicAuth": false }' >> /tmp/grafana-datasource.json;
    fi

    curl $GRAFANA_BASIC_AUTH -XPOST -H 'Content-Type: application/json' localhost:3000/api/datasources -d @/tmp/grafana-datasource.json
    rm /tmp/grafana-datasource.json
    
    if [ -f /opt/grafana-dashboard.json ]; then
        echo '{ "meta": {"isStarred": true}, "dashboard":' > /tmp/grafana-dashboard.json
        cat /opt/grafana-dashboard.json | jq -r 'del(.uid) | del(.id)' >> /tmp/grafana-dashboard.json
        echo '}' >> /tmp/grafana-dashboard.json
        curl $GRAFANA_BASIC_AUTH -XPOST -H 'Content-Type: application/json' localhost:3000/api/dashboards/db -d @/tmp/grafana-dashboard.json
    fi
}

# Setup x-pack security also on Kibana configs where applicable
if [ -f "/etc/kibana/kibana.yml" ]; then

    if [ "$BIND_TO_ALL" == "true" ]; then
        echo "server.host: 0.0.0.0" | sudo tee -a /etc/kibana/kibana.yml
    else
        echo "server.host: $(hostname -i)" | sudo tee -a /etc/kibana/kibana.yml
    fi

    echo "xpack.security.enabled: $security_enabled" | sudo tee -a /etc/kibana/kibana.yml
    echo "xpack.monitoring.enabled: $monitoring_enabled" | sudo tee -a /etc/kibana/kibana.yml

    if [ "$security_enabled" == "true" ]; then
        echo "elasticsearch.username: \"kibana\"" | sudo tee -a /etc/kibana/kibana.yml
        echo "elasticsearch.password: \"$client_pwd\"" | sudo tee -a /etc/kibana/kibana.yml
    fi

    systemctl daemon-reload
    systemctl enable kibana.service
    sudo service kibana restart
fi

if [ -f "/etc/grafana/grafana.ini" ]; then
    sudo rm /etc/grafana/grafana.ini

    if [ "$security_enabled" == "true" ]; then
        cat <<EOF >>/etc/grafana/grafana.ini
[security]
admin_user = $client_user
admin_password = $client_pwd
EOF
    else
        cat <<EOF >>/etc/grafana/grafana.ini
[auth.anonymous]
enabled = true
org_name = Main Org.
org_role = Admin
EOF
    fi

    sudo /bin/systemctl daemon-reload
    sudo /bin/systemctl enable grafana-server.service
    sudo service grafana-server start

    setup_grafana_dashboard;
fi

if [ -d "/usr/share/cerebro/" ]; then
    CEREBRO_CONFIG_PATH="$(echo /usr/share/cerebro/cerebro*/conf/application.conf)"
    if [ "$security_enabled" == "true" ]; then
        sudo sed -i "s/.{?BASIC_AUTH_USER}/$client_user/ig" $CEREBRO_CONFIG_PATH
        sudo sed -i "s/.{?BASIC_AUTH_PWD}/$client_pwd/ig" $CEREBRO_CONFIG_PATH
        sudo sed -i 's/.{?AUTH_TYPE}/"basic"/ig' $CEREBRO_CONFIG_PATH
    fi
    sudo systemctl restart cerebro        
fi
