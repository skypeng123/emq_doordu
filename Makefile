PROJECT = emq_doordu
PROJECT_DESCRIPTION = EMQ Doordu
PROJECT_VERSION = 1.2

BUILD_DEPS = emqttd cuttlefish amqp_client
dep_emqttd = git https://github.com/emqtt/emqttd master
dep_cuttlefish = git https://github.com/emqtt/cuttlefish
dep_amqp_client = git https://github.com/jbrisbin/amqp_client.git master

ERLC_OPTS += +debug_info
ERLC_OPTS += +'{parse_transform, lager_transform}'

TEST_DEPS = emqttc
dep_emqttc = git https://github.com/emqtt/emqttc.git master

TEST_ERLC_OPTS += +debug_info
TEST_ERLC_OPTS += +'{parse_transform, lager_transform}'

NO_AUTOPATCH = cuttlefish

COVER = true

include erlang.mk

app:: rebar.config

app.config::
	./deps/cuttlefish/cuttlefish -l info -e etc/ -c etc/emq_doordu.conf -i priv/emq_doordu.schema -d data
