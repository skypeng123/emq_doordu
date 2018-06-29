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

-module(emq_doordu_cli).

-behaviour(ecpool_worker).

-include("emq_doordu.hrl").

-include_lib("emqttd/include/emqttd.hrl").

-include_lib("amqp_client/include/amqp_client.hrl").

-export([connect/1, q/1, publish/2]).

%%--------------------------------------------------------------------
%% Redis Connect/Query
%%--------------------------------------------------------------------

connect(Opts) ->  
  %io:format("Opts: ~p ~n", [Opts]),
  Args = #amqp_params_network{   
        username           = list_to_binary(proplists:get_value(amqp_username, Opts)),
        password           = list_to_binary(proplists:get_value(amqp_password, Opts)),
        host               = proplists:get_value(amqp_host, Opts),
        port               = proplists:get_value(amqp_port, Opts),
        heartbeat          = proplists:get_value(amqp_heartbeat, Opts)
      },
  %io:format("Args: ~p ~n", [Args]),
  {ok, Connection} = amqp_connection:start(Args),
  amqp_connection:open_channel(Connection).

%% amqp Query.
q(Declare) ->
  ecpool:with_client(?APP, fun(C) -> amqp_channel:call(C, Declare) end).


publish(Declare,Payload) ->
  ecpool:with_client(?APP, fun(C) -> amqp_channel:cast(C, Declare,Payload) end).


