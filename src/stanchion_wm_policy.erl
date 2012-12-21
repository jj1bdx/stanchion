%% -------------------------------------------------------------------
%%
%% Copyright (c) 2007-2012 Basho Technologies, Inc.  All Rights Reserved.
%%
%% -------------------------------------------------------------------

-module(stanchion_wm_policy).

-export([init/1,
         service_available/2,
         is_authorized/2,
         content_types_provided/2,
         malformed_request/2,
         to_json/2,
         allowed_methods/2,
         content_types_accepted/2,
         accept_body/2,
         delete_resource/2]).

-include("stanchion.hrl").
-include_lib("webmachine/include/webmachine.hrl").

init(Config) ->
    %% Check if authentication is disabled and
    %% set that in the context.
    AuthBypass = proplists:get_value(auth_bypass, Config),
    % eval every atoms to make binary_to_existing_atom/2 work.
    {ok, #context{auth_bypass=AuthBypass}}.

-spec service_available(term(), term()) -> {true, term(), term()}.
service_available(RD, Ctx) ->
    stanchion_wm_utils:service_available(RD, Ctx).

-spec malformed_request(term(), term()) -> {false, term(), term()}.
malformed_request(RD, Ctx) ->
    {false, RD, Ctx}.

%% @doc Check that the request is from the admin user
is_authorized(RD, Ctx=#context{auth_bypass=AuthBypass}) ->
    AuthHeader = wrq:get_req_header("authorization", RD),
    case stanchion_wm_utils:parse_auth_header(AuthHeader, AuthBypass) of
        {ok, AuthMod, Args} ->
            case AuthMod:authenticate(RD, Args) of
                ok ->
                    %% Authentication succeeded
                    {true, RD, Ctx};
                {error, _Reason} ->
                    %% Authentication failed, deny access
                    stanchion_response:api_error(access_denied, RD, Ctx)
            end
    end.

%% @doc Get the list of methods this resource supports.
-spec allowed_methods(term(), term()) -> {[atom()], term(), term()}.
allowed_methods(RD, Ctx) ->
    {['GET', 'PUT', 'DELETE'], RD, Ctx}.

-spec content_types_provided(term(), term()) ->
                                    {[{string(), atom()}], term(), term()}.
content_types_provided(RD, Ctx) ->
    {[{"application/json", to_xml}], RD, Ctx}.

-spec content_types_accepted(term(), term()) ->
                                    {[{string(), atom()}], term(), term()}.
content_types_accepted(RD, Ctx) ->
    {[{"application/json", accept_body}], RD, Ctx}.

-spec to_json(term(), term()) ->
                     {{'halt', term()}, #wm_reqdata{}, term()}.
to_json(RD, Ctx) ->
    Bucket = wrq:path_info(bucket, RD),
    stanchion_response:list_buckets_response(Bucket, RD, Ctx).

%% @doc Process the request body on `PUT'.
accept_body(RD, Ctx) ->
    Bucket = list_to_binary(wrq:path_info(bucket, RD)),
    Body = wrq:req_body(RD),
    %% @TODO Handle json decoding exceptions
    ParsedBody = mochijson2:decode(Body),
    FieldList = stanchion_wm_utils:json_to_proplist(ParsedBody),
    case stanchion_utils:set_bucket_policy(Bucket,
                                           FieldList) of
        ok ->
            {true, RD, Ctx};
        {error, Reason} ->
            stanchion_response:api_error(Reason, RD, Ctx)
    end.

%% @doc Callback for deleting an object.
-spec delete_resource(#wm_reqdata{}, #context{}) -> {true, #wm_reqdata{}, #context{}}.
delete_resource(RD, Ctx) ->
    Bucket = list_to_binary(wrq:path_info(bucket, RD)),
    RequesterId = list_to_binary(wrq:get_qs_value("requester", "", RD)),
    _ = lager:debug("Bucket: ~p Requester: ~p", [Bucket, RequesterId]),

    case stanchion_utils:delete_bucket_policy(Bucket, RequesterId) of
        ok ->
            % @TODO: does 204 really good? how does s3 works?
            {{halt, 204}, RD, Ctx};
        {error, Reason} ->
            stanchion_response:api_error(Reason, RD, Ctx)
    end.

