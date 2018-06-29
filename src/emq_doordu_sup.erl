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

-module(emq_doordu_sup).

-behaviour(supervisor).

-include("emq_doordu.hrl").

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->	
	{ok,PoolSize} = application:get_env(?APP, amqp_pool_size),
	{ok,Host} = application:get_env(?APP, amqp_host),
	{ok,Port} = application:get_env(?APP, amqp_port),
	{ok,User} = application:get_env(?APP, amqp_username),
	{ok,PWD} = application:get_env(?APP, amqp_password),
	{ok,Heartbeat} = application:get_env(?APP, amqp_heartbeat),
	{ok,AutoReconnect} = application:get_env(?APP, auto_reconnect),
	
	PoolSpec = ecpool:pool_spec(?APP, ?APP, emq_doordu_cli, [
			{pool_size, PoolSize},
			{amqp_host, Host},
			{amqp_port, Port},
			{amqp_username, User},
			{amqp_password, PWD},
			{amqp_heartbeat, Heartbeat},
			{auto_reconnect,AutoReconnect}
		]),
	
    {ok, {{one_for_one, 10, 100}, [PoolSpec]}}.

