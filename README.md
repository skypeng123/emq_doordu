
EMQ Doordu
============

Configuration
-------------

etc/emq_doordu.conf:

```
##Call message cmd
doordu.call_cmd = makeCall

##Hangup call message cmd
doordu.hangup_cmd = hangUpCall

##send offline message : on / off
doordu.offline_message = off

##sent stats : on / off
doordu.sent_stats = on

```

Author
------

Jipeng at doordu.com

Make
-----------------
vim emq-relx/Makefile

DEPS += emq_doordu
dep_plugin_name = git https://github.com/skypeng123/emq_doordu

vim emq-relx/relx.config

{emq_doordu, load}


Plugin and Hooks
-----------------

[Plugin Design](http://docs.emqtt.com/en/latest/design.html#plugin-design)

[Hooks Design](http://docs.emqtt.com/en/latest/design.html#hooks-design)

License
-------

Apache License Version 2.0
