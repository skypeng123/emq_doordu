%%--------------------------------------------------------------------
%% Copyright (c) 2013-2017 EMQ Enterprise, Inc. (http://emqtt.io)
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

-module(emq_doordu).

-author("Jipeng <jip@doordu.com>").

-include_lib("emqttd/include/emqttd.hrl").

-include_lib("emqttd/include/emqttd_protocol.hrl").

-include_lib("amqp_client/include/amqp_client.hrl").

%% Mnesia Callbacks
-export([mnesia/1]).

-boot_mnesia({mnesia, [boot]}).
-copy_mnesia({mnesia, [copy]}).

-export([load/1, unload/0]).

%% Hooks functions

-export([on_session_subscribed/4,on_client_unsubscribe/4,on_message_publish/2, on_message_delivered/4,on_message_acked/4]).

-record(hangup_commands, {transaction_id, created_at}).

-record(topic_members, {topic,client_id}).

%% Called when the plugin application start
load(Env) ->
    emqttd:hook('session.subscribed', fun ?MODULE:on_session_subscribed/4, [Env]),
    emqttd:hook('client.unsubscribe', fun ?MODULE:on_client_unsubscribe/4, [Env]),
    emqttd:hook('message.publish', fun ?MODULE:on_message_publish/2, [Env]),
    emqttd:hook('message.delivered', fun ?MODULE:on_message_delivered/4, [Env]),
    emqttd:hook('message.acked', fun ?MODULE:on_message_acked/4, [Env]).  


%%--------------------------------------------------------------------
%% Mnesia callbacks
%%--------------------------------------------------------------------

mnesia(boot) ->
    ok = ekka_mnesia:create_table(topic_members,[
                {ram_copies, [node()]},               
                {type,bag},
                {record_name, topic_members},
                {attributes, record_info(fields, topic_members)}]),

    %% Global Session Table
    ok = ekka_mnesia:create_table(hangup_commands, [
                {ram_copies, [node()]},
                {record_name, hangup_commands},
                {attributes, record_info(fields, hangup_commands)}]);

mnesia(copy) ->
    ok = ekka_mnesia:copy_table(topic_members,ram_copies),
    ok = ekka_mnesia:copy_table(hangup_commands,ram_copies).

%%订阅时将用户订阅主题关系保存至topic_members表(ram)
on_session_subscribed(ClientId, Username, {Topic, Opts}, _Env) ->
    %io:format("session(~s) subscribed: ~p~n", [ClientId, {Topic, Opts}]),
    add_topic_member(Topic,ClientId),
    {ok, {Topic, Opts}}.

%%取消订阅时将用户订阅主题关系从topic_members表(ram)中删除
on_client_unsubscribe(ClientId, Username, {Topic, Opts}, _Env) ->
    %io:format("session(~s) unsubscribe: ~p~n", [ClientId, {Topic, Opts}]),
    del_topic_member(Topic,ClientId),
    {ok, {Topic, Opts}}.

%% 消息发送
on_message_publish(Message = #mqtt_message{topic = <<"$SYS/", _/binary>>}, _Env) ->
    {ok, Message};

on_message_publish(Message, _Env) ->
    publish_event(Message,_Env),
    {ok, Message}.


on_message_delivered(ClientId, Username, Message = #mqtt_message{payload = Payload}, _Env) ->
    %io:format("delivered to client(~s/~s): ~s~n", [Username, ClientId, emqttd_message:format(Message)]),
    case jsx:is_json(Payload) andalso is_json(Payload) of
        true -> 
            PayloadMap = jsx:decode(Payload, [return_maps]), 
            TransactionID = maps:get(<<"transactionID">>,PayloadMap,null),
            Cmd = maps:get(<<"cmd">>,PayloadMap,null),
            ExpiredAt = maps:get(<<"expiredAt">>,PayloadMap,null),
            case TransactionID /= null andalso Cmd /= null andalso ExpiredAt /= null andalso binary_to_list(Cmd) == proplists:get_value(call_cmd, _Env, 0) of
                true -> 
                    case check_call_payload(TransactionID, ExpiredAt, PayloadMap, _Env) of  
                        {ok,NewPayload} ->
                            PayloadJson = jsx:encode(NewPayload),
                            _Message = Message#mqtt_message{payload = PayloadJson},
                            {ok,_Message};
                        {bad,_} ->
                            {stop,Message}
                    end;
                false ->                      
                    {ok,Message}
            end;
        false ->            
            {ok, Message}         
    end.    

on_message_acked(ClientId, Username, Message, _Env) ->
    acked_event(ClientId, Message, _Env),
    {ok, Message}.


%%发送事件
publish_event(Message = #mqtt_message{payload = Payload}, _Env) ->
    %io:format("payload: ~p~n",[Payload]),
    %io:format("payload is_json: ~p~n",[jsx:is_json(Payload) andalso is_json(Payload)]),
    %jsx:is_json判断不准确，<<123123123123>>也会认为是json，故需再加一个自定义is_json
    case jsx:is_json(Payload) andalso is_json(Payload) of 
        true ->
            %发送json消息
            publish_message(json, Message, _Env);      
        false ->
            %发送普通字符串消息
            publish_message(string, Message)
    end.

%%到达事件
acked_event(ClientId, Message = #mqtt_message{payload = Payload,topic = Topic}, _Env) ->
    case jsx:is_json(Payload) andalso is_json(Payload) of 
        true ->    
            PayloadMap = jsx:decode(Payload, [return_maps]),
            TransactionID = maps:get(<<"transactionID">>,PayloadMap,null),
            Cmd = maps:get(<<"cmd">>,PayloadMap,null),          
            %发送消息到达统计数据
            case TransactionID /= null andalso Cmd /= null of
                true  -> publish_stats(acked, ClientId, Cmd, TransactionID, Topic, _Env);
                false -> ok
            end;                
        false ->
            ok
    end.


%%发送普通字符串消息
publish_message(string, Message) ->
    {ok, Message}.

%%发送JSON消息
publish_message(json, Message = #mqtt_message{topic = Topic, payload = Payload}, _Env) ->
    PayloadMap = jsx:decode(Payload, [return_maps]),
    TransactionID = maps:get(<<"transactionID">>,PayloadMap,null),
    Cmd = maps:get(<<"cmd">>,PayloadMap,null),  

    %发送统计数据
    case TransactionID /= null andalso Cmd /= null of
        true  -> publish_stats(publish, Cmd, TransactionID, Topic, _Env);
        false -> ok
    end,

    %发送消息为挂断消息时保存至hangup_commands表(ram)         
    case TransactionID /= null andalso Cmd /= null andalso binary_to_list(Cmd) == proplists:get_value(hangup_cmd, _Env, 0) of 
        true -> add_hangup(TransactionID,timestamp());            
        false -> ok
    end.

%%呼叫消息内容检查
check_call_payload(TransactionID, ExpiredAt, PayloadMap, _Env) ->
    %检查是否已挂断
    case lookup_hangup(TransactionID) of
        [_] -> {bad,PayloadMap};
        [] -> 
            %检查呼叫消息是否过期
            case ExpiredAt < timestamp() of
                false -> {ok,PayloadMap};
                true -> 
                    case proplists:get_value(offline_message, _Env, 0) == on of  
                        false -> {bad,PayloadMap};
                        true ->
                            _Payload = message_expired(PayloadMap),                      
                            {ok,_Payload}
                    end
            end 
    end.


%%发布消息统计分发
publish_stats(publish, Cmd, TransactionID, Topic, _Env) ->
    case on == proplists:get_value(send_stats, _Env, 0) of
        true ->            
            {_,ClientIds} = lookup_topic_member(Topic),
            %%io:format("topic members ~w ~w~n", [Message#mqtt_message.topic,Members]),
            MemberCount = length(ClientIds),
            OnlineStatus = client_online_status(ClientIds),
            %%io:format("OnlineStatus: ~p ~p~n", [ClientIds,OnlineStatus]),
            AttrData = #{serverIp =>list_to_atom(get_ip()) ,serverName =>emq,dateTime =>timestamp()},    
            MessageBody = #{transactionID =>TransactionID,cmd=>Cmd, topic=>Topic, members=>MemberCount,onlineStatus=>OnlineStatus,publishTime=>timestamp()},
            Stats = #{attr => AttrData,messageType => publish, body => MessageBody},  
            %发送统计至rabbitMQ                              
            publish_rabbitmq(jsx:encode(Stats));  
        false ->
            stop
    end.

%%接收消息统计分发
publish_stats(acked, ClientId, Cmd, TransactionID, Topic, _Env) ->
    case on == proplists:get_value(send_stats, _Env, 0) of
        true ->
            %%发送统计至rabbitMQ                    
            AttrData = #{serverIp =>list_to_atom(get_ip()) ,serverName =>emq,dateTime =>timestamp()},      
            MessageBody = #{transactionID =>TransactionID,cmd=>Cmd, topic=>Topic, clientId=>ClientId, receiveTime=>timestamp()},
            Stats = #{attr => AttrData, messageType => received, body => MessageBody},  
            %发送统计至rabbitMQ                  
            publish_rabbitmq(jsx:encode(Stats));
        false ->
            stop
    end.

%%存储挂断消息
add_hangup(TransactionID,CreatedAt) ->
    Hangup = #hangup_commands{transaction_id = TransactionID,
                        created_at     = CreatedAt},
    mnesia:transaction(fun add_hangup_/1, [Hangup]).

add_hangup_(Hangup = #hangup_commands{transaction_id = TransactionID}) ->
    case mnesia:wread({hangup_commands, TransactionID}) of
        []  -> mnesia:write(Hangup);
        [_] -> mnesia:abort("hangup already exist")
    end.
%%查找挂断消息
lookup_hangup(TransactionID) -> 
    mnesia:dirty_read(hangup_commands, TransactionID).
    
    
%%消息设置过期状态
message_expired(Payload) ->
    case maps:is_key(<<"isExpired">>,Payload) of 
        true -> Payload#{isExpired := true};
        false -> Payload#{isExpired => true}
    end.

%%查询Topic下的订阅用户
lookup_topic_member(Topic) ->
  Fun = fun() ->
      Pat = #topic_members{topic = Topic, client_id = '$2'},
      Guard = [],
      mnesia:select(topic_members,[{Pat, Guard, ['$2']}])
    end,
  mnesia:transaction(Fun).

%%存储topic订阅用户
add_topic_member(Topic,ClientId) ->
  Record = #topic_members{topic = Topic,client_id = ClientId},
  mnesia:transaction(fun() -> mnesia:write(Record) end).

%%删除topic订阅用户
del_topic_member(Topic,ClientId) ->
  Record = #topic_members{topic = Topic,client_id = ClientId},
  mnesia:transaction(fun() -> mnesia:delete_object(Record) end).

%%查询用户在线状态
client_online_status(Cids) ->
  lists:map(fun(X) ->
    {X,client_online_status_(X)}
  end, Cids).

client_online_status_(ClientId) ->
    case emqttd_mgmt:client(ClientId) of
        [] -> 0;
        [_] -> 1            
    end.

%%发送统计数据到rabbitmq
 publish_rabbitmq(Payload) ->
    io:format("publish stats to rabbitmq: ~p ~n", [Payload]),

    X = <<"emq.topic">>,
    T = <<"topic">>,
    BindKey = <<"#">>,
    Q = <<"emq_queue">>,
    
    %创建队列
    QueueDeclare = #'queue.declare'{queue = Q},
    emq_doordu_cli:q(QueueDeclare),

    %创建Exchange
    ExchangeDeclare = #'exchange.declare'{exchange = X, type = T},
    emq_doordu_cli:q(ExchangeDeclare),

    %绑定queue
    QueueBind = #'queue.bind'{queue = Q,exchange = X,routing_key = BindKey},
    emq_doordu_cli:q(QueueBind),

    %发送消息
    BasicPublish = #'basic.publish'{exchange = X, routing_key = Q},
    emq_doordu_cli:publish(BasicPublish, _MsgPayload = #amqp_msg{payload = Payload}).
        
timestamp() ->  
    {M, S, _} = os:timestamp(),  
    M * 1000000 + S.
    
get_ip() ->
  {ok,Ips} = inet:getif(),
  [{Ip,_,_}|_] = Ips,
  L = lists:map(fun(Int) -> integer_to_list(Int) end, tuple_to_list(Ip)),
  string:join(L,".").

%% 简单JSON字符判断函数
is_json(Payload) ->
    case re:run(Payload, "^{(.*)}$", [{capture, all, list}]) of
        {match, [_,_]} ->
            true;
        nomatch ->
            false
    end.

%% Called when the plugin application stop
unload() ->
    emqttd:unhook('session.subscribed', fun ?MODULE:on_session_subscribed/4),
    emqttd:unhook('client.unsubscribe', fun ?MODULE:on_client_unsubscribe/4),
    emqttd:unhook('message.publish', fun ?MODULE:on_message_publish/2),
    emqttd:unhook('message.delivered', fun ?MODULE:on_message_delivered/4),
    emqttd:unhook('message.acked', fun ?MODULE:on_message_acked/4).