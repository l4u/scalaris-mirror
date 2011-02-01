%  @copyright 2010 Konrad-Zuse-Zentrum fuer Informationstechnik Berlin

%   Licensed under the Apache License, Version 2.0 (the "License");
%   you may not use this file except in compliance with the License.
%   You may obtain a copy of the License at
%
%       http://www.apache.org/licenses/LICENSE-2.0
%
%   Unless required by applicable law or agreed to in writing, software
%   distributed under the License is distributed on an "AS IS" BASIS,
%   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%   See the License for the specific language governing permissions and
%   limitations under the License.

%% @author Nico Kruber <kruber@zib.de>
%% @doc    dht_node move procedure
%% @end
%% @version $Id$
-module(dht_node_move).
-author('kruber@zib.de').
-vsn('$Id$').

-include("transstore/trecords.hrl").
-include("scalaris.hrl").

%-define(TRACE(X,Y), ct:pal(X,Y)).
-define(TRACE(X,Y), ok).
-define(TRACE_SEND(Pid, Msg), ?TRACE("[ ~.0p ] to ~.0p: ~.0p~n", [self(), Pid, Msg])).
-define(TRACE1(Msg, State),
        ?TRACE("[ ~.0p ]~n  Msg: ~.0p~n"
               "  State: pred: ~.0p~n"
               "         node: ~.0p~n"
               "         succ: ~.0p~n"
               "   slide_pred: ~.0p~n"
               "   slide_succ: ~.0p~n"
               "      msg_fwd: ~.0p~n"
               "     db_range: ~.0p~n",
               [self(), Msg, dht_node_state:get(State, pred),
                dht_node_state:get(State, node), dht_node_state:get(State, succ),
                dht_node_state:get(State, slide_pred), dht_node_state:get(State, slide_succ),
                dht_node_state:get(State, msg_fwd), dht_node_state:get(State, db_range)])).

-export([process_move_msg/2,
         can_slide_succ/3, can_slide_pred/3,
         rm_notify_new_pred/4, rm_send_node_change/4,
         make_slide/5,
         make_slide_leave/1, make_jump/4,
         check_config/0]).

-ifdef(with_export_type_support).
-export_type([move_message/0]).
-endif.

-type abort_reason() ::
    ongoing_slide |
    target_id_not_in_range |
    % moving node and its succ or pred did not share the same knowledge about
    % each other or the pred/succ changed during a move:
    wrong_pred_succ_node |
    % received slide_succ with different parameters than previously set up before sending slide_pred to succ:
    changed_parameters |
    % node received data but its interval is not adjacent to the range of the node: (should never occur - error in the protocoll!) or
    % node received data_ack but the send interval is not correct anymore, i.e. at either end of our range
    {wrong_interval, MyRange::intervals:interval(), MovingDataInterval::intervals:interval()} |
    % node received data but previous data still exists (should never occur - error in the protocoll!)
    existing_data |
    notify_other_timeout | % tried to notify my successor/predecessor of a move
    notify_other_continue_timeout | % tried to notify my successor/predecessor of a continued move
    send_data_timeout | % sent data to succ/pred but no reply yet
    rcv_data_timeout | % sent req_data to succ/pred but no reply yet
    rcv_delta_timeout | % sent data_ack to succ/pred but no reply yet
    send_delta_timeout | % sent delta data to succ/pred but no reply yet
    scheduled_leave | % tried to continue a slide but a leave was already scheduled
    next_op_mismatch |
    {protocol_error, string()}.

-type result_message() :: {move, result, Tag::any(), Reason::abort_reason() | ok}.

-type move_message() ::
    {move, start_slide, pred | succ, TargetId::?RT:key(), Tag::any(), SourcePid::comm:erl_local_pid() | null} |
    {move, start_jump, TargetId::?RT:key(), Tag::any(), SourcePid::comm:erl_local_pid() | null} |
    {move, slide, OtherType::slide_op:type(), MoveFullId::slide_op:id(), InitNode::node:node_type(), TargetNode::node:node_type(), TargetId::?RT:key(), Tag::any()} |
    {move, slide_get_mte, OtherType::slide_op:type(), MoveFullId::slide_op:id(), InitNode::node:node_type(), TargetNode::node:node_type(), TargetId::?RT:key(), Tag::any()} |
    {move, slide_w_mte, OtherType::slide_op:type(), MoveFullId::slide_op:id(), InitNode::node:node_type(), TargetNode::node:node_type(), TargetId::?RT:key(), Tag::any(), MaxTransportEntries::pos_integer()} |
    {move, slide, OtherType::slide_op:type(), MoveFullId::slide_op:id(), InitNode::node:node_type(), TargetNode::node:node_type(), TargetId::?RT:key(), Tag::any(), NextOp::slide_op:next_op()} |
    {move, my_mte, MoveFullId::slide_op:id(), MaxTransportEntries::pos_integer()} | % max transport entries from a partner
    {move, change_op, MoveFullId::slide_op:id(), TargetId::?RT:key(), NextOp::slide_op:next_op()} | % message from pred to succ that it has created a new (incremental) slide if succ has already set up the slide
    {move, change_id, MoveFullId::slide_op:id()} | % message from succ to pred if pred has already set up the slide
    {move, change_id, MoveFullId::slide_op:id(), TargetId::?RT:key(), NextOp::slide_op:next_op()} | % message from succ to pred if pred has already set up the slide but succ made it an incremental slide
    {move, slide_abort, pred | succ, MoveFullId::slide_op:id(), Reason::abort_reason()} |
    {move, node_update, Tag::{move, slide_op:id()}} | % message from RM that it has changed the node's id to TargetId
    {move, rm_new_pred, Tag::{move, slide_op:id()}} | % message from RM that it knows the pred we expect
    {move, req_data, MoveFullId::slide_op:id()} |
    {move, data, MovingData::?DB:db_as_list(), MoveFullId::slide_op:id()} |
    {move, data_ack, MoveFullId::slide_op:id()} |
    {move, delta, ChangedData::?DB:db_as_list(), DeletedKeys::[?RT:key()], MoveFullId::slide_op:id()} |
    {move, delta_ack, MoveFullId::slide_op:id()} |
    {move, delta_ack, MoveFullId::slide_op:id(), continue, NewSlideId::slide_op:id()} |
    {move, delta_ack, MoveFullId::slide_op:id(), OtherType::slide_op:type(), NewSlideId::slide_op:id(), InitNode::node:node_type(), TargetNode::node:node_type(), TargetId::?RT:key(), Tag::any(), MaxTransportEntries::pos_integer()} |
    {move, done, MoveFullId::slide_op:id()} |
    % timeout messages:
    {move, notify_other_timeout, MoveFullId::slide_op:id()} | % tried to notify my successor/predecessor of a move
    {move, notify_other_continue_timeout, MoveFullId::slide_op:id(), NextOpId::slide_op:id()} | % tried to notify my successor/predecessor of a continued move
    {move, send_data_timeout, MoveFullId::slide_op:id()} | % sent data to succ/pred but no reply yet
    {move, rcv_data_timeout, MoveFullId::slide_op:id()} | % sent req_data to succ/pred but no reply yet
    {move, rcv_delta_timeout, MoveFullId::slide_op:id()} | % sent data_ack to succ/pred but no reply yet
    {move, send_delta_timeout, MoveFullId::slide_op:id(), ChangedData::?DB:db_as_list(), DeletedKeys::[?RT:key()]} % sent delta data to succ/pred but no reply yet
.

%% @doc Processes move messages for the dht_node and implements the node move
%%      protocol.
-spec process_move_msg(move_message(), dht_node_state:state()) -> dht_node_state:state().
process_move_msg({move, start_slide, PredOrSucc, TargetId, Tag, SourcePid} = _Msg, State) ->
    ?TRACE1(_Msg, State),
    make_slide(State, PredOrSucc, TargetId, Tag, SourcePid);

process_move_msg({move, start_jump, TargetId, Tag, SourcePid} = _Msg, State) ->
    ?TRACE1(_Msg, State),
    make_jump(State, TargetId, Tag, SourcePid);

process_move_msg({move, notify_other_timeout, MoveFullId} = _Msg, MyState) ->
    ?TRACE1(_Msg, MyState),
    WorkerFun =
        fun(SlideOp, _PredOrSucc, State) ->
                MaxRetries = get_notify_other_retries(),
                case (slide_op:get_timeouts(SlideOp) < MaxRetries) of
                    true ->
                        NewSlideOp = slide_op:inc_timeouts(SlideOp),
                        notify_other(NewSlideOp, State);
                    _ ->
                        % if the message was received by succ, it will itself run
                        % into a timeout since we do not reply to it anymore
                        % -> do not send abort message
                        abort_slide(State, SlideOp, notify_other_timeout, false)
                end
        end,
    safe_operation(WorkerFun, MyState, MoveFullId,
                   [wait_for_other_mte, wait_for_change_op, wait_for_change_id,
                    wait_for_req_data, wait_for_data], both, notify_other_timeout);

process_move_msg({move, notify_other_continue_timeout, OldMoveFullId, NextOpId} = _Msg, MyState) ->
    ?TRACE1(_Msg, MyState),
    WorkerFun =
        fun(SlideOp, _PredOrSucc, State) ->
                MaxRetries = get_notify_other_retries(),
                case (slide_op:get_timeouts(SlideOp) < MaxRetries) of
                    true ->
                        NewSlideOp = slide_op:inc_timeouts(SlideOp),
                        notify_other_in_delta_ack(OldMoveFullId, NewSlideOp, State);
                    _ ->
                        % if the message was received by succ, it will itself run
                        % into a timeout since we do not reply to it anymore
                        % -> do not send abort message
                        abort_slide(State, SlideOp, notify_other_continue_timeout, false)
                end
        end,
    safe_operation(WorkerFun, MyState, NextOpId, [wait_for_change_id, wait_for_change_op], both, notify_other_continue_timeout);

% notification from predecessor/successor that it wants to slide with our node
process_move_msg({move, slide, OtherType, MoveFullId, OtherNode,
                  OtherTargetNode, TargetId, Tag} = _Msg, State) ->
    ?TRACE1(_Msg, State),
    setup_slide(State, slide_op:other_type_to_my_type(OtherType), MoveFullId,
                OtherTargetNode, OtherNode, TargetId, Tag, unknown,
                null, slide, {none});

% notification from predecessor/successor that it wants to slide with our node
process_move_msg({move, slide_get_mte, OtherType, MoveFullId, OtherNode,
                  OtherTargetNode, TargetId, Tag} = _Msg, State) ->
    ?TRACE1(_Msg, State),
    setup_slide(State, slide_op:other_type_to_my_type(OtherType), MoveFullId,
                OtherTargetNode, OtherNode, TargetId, Tag, unknown,
                null, slide_get_mte, {none});

% notification from predecessor/successor that it wants to slide with our node
process_move_msg({move, slide_w_mte, OtherType, MoveFullId, OtherNode,
                  OtherTargetNode, TargetId, Tag, MaxTransportEntries} = _Msg, State) ->
    ?TRACE1(_Msg, State),
    setup_slide(State, slide_op:other_type_to_my_type(OtherType), MoveFullId,
                OtherTargetNode, OtherNode, TargetId, Tag, MaxTransportEntries,
                null, slide_w_mte, {none});

% notification from predecessor/successor that it wants to slide with our node
% (incremental slide)
process_move_msg({move, slide, OtherType, MoveFullId, OtherNode,
                  OtherTargetNode, TargetId, Tag, NextOp} = _Msg, State) ->
    ?TRACE1(_Msg, State),
    setup_slide(State, slide_op:other_type_to_my_type(OtherType), MoveFullId,
                OtherTargetNode, OtherNode, TargetId, Tag, unknown,
                null, slide, NextOp);

% notification from predecessor/successor that the move is a noop, i.e. alread
% finished
process_move_msg({move, done, MoveFullId} = _Msg, MyState) ->
    ?TRACE1(_Msg, MyState),
    WorkerFun =
        fun(SlideOp, PredOrSucc, State) ->
                SlideOp1 = slide_op:reset_timer(SlideOp), % reset previous timeouts
                notify_source_pid(slide_op:get_source_pid(SlideOp1),
                                  {move, result, slide_op:get_tag(SlideOp1), ok}),
                dht_node_state:set_slide(State, PredOrSucc, null)
        end,
    safe_operation(WorkerFun, MyState, MoveFullId, [wait_for_other_mte], both, my_mte);

process_move_msg({move, my_mte, MoveFullId, OtherMTE} = _Msg, MyState) ->
    ?TRACE1(_Msg, MyState),
    WorkerFun =
        fun(SlideOp, PredOrSucc, State) ->
                SlideOp1 = slide_op:reset_timer(SlideOp), % reset previous timeouts
                % simply re-create the slide (TargetId or NextOp have changed)
                State1 = dht_node_state:set_slide(State, PredOrSucc, null),
                exec_setup_slide_not_found(
                  {ok, slide_op:get_type(SlideOp1)}, State1,
                  slide_op:get_id(SlideOp1), slide_op:get_node(SlideOp1),
                  slide_op:get_target_id(SlideOp1), slide_op:get_tag(SlideOp1),
                  OtherMTE, slide_op:get_source_pid(SlideOp1), my_mte, {none})
        end,
    safe_operation(WorkerFun, MyState, MoveFullId, [wait_for_other_mte], both, my_mte);

process_move_msg({move, change_op, MoveFullId, TargetId, NextOp} = _Msg, MyState) ->
    ?TRACE1(_Msg, MyState),
    WorkerFun =
        fun(SlideOp, pred, State) ->
                SlideOp1 = slide_op:reset_timer(SlideOp), % reset previous timeouts
                % simply re-create the slide (TargetId or NextOp have changed)
                NewSlideOp = slide_op:new_slide(
                               MoveFullId, slide_op:get_type(SlideOp1),
                               TargetId, slide_op:get_tag(SlideOp1),
                               slide_op:get_source_pid(SlideOp1),
                               slide_op:get_other_max_entries(SlideOp1),
                               NextOp, State),
                NewSlideOp2 = slide_op:set_setup_at_other(NewSlideOp),
                NewSlideOp3 = slide_op:set_phase(NewSlideOp2, wait_for_data),
                State1 = dht_node_state:set_slide(State, pred, null), % just in case
                notify_other(NewSlideOp3, State1)
        end,
    safe_operation(WorkerFun, MyState, MoveFullId, [wait_for_change_op], pred, change_op);

process_move_msg({move, change_id, MoveFullId} = _Msg, MyState) ->
    ?TRACE1(_Msg, MyState),
    WorkerFun =
        fun(SlideOp, succ, State) ->
                SlideOp1 = slide_op:reset_timer(SlideOp), % reset previous timeouts
                change_my_id(State, SlideOp1)
        end,
    safe_operation(WorkerFun, MyState, MoveFullId, [wait_for_change_id], succ, change_id);

process_move_msg({move, change_id, MoveFullId, TargetId, NextOp} = _Msg, MyState) ->
    ?TRACE1(_Msg, MyState),
    WorkerFun =
        fun(SlideOp, succ, State) ->
                SlideOp1 = slide_op:reset_timer(SlideOp), % reset previous timeouts
                % simply re-create the slide (TargetId or NextOp might have changed)
                State1 = dht_node_state:set_slide(State, succ, null),
                exec_setup_slide_not_found(
                  {ok, slide_op:get_type(SlideOp1)}, State1,
                  slide_op:get_id(SlideOp1), slide_op:get_node(SlideOp1), TargetId,
                  slide_op:get_tag(SlideOp1), slide_op:get_other_max_entries(SlideOp1),
                  slide_op:get_source_pid(SlideOp1), change_id, NextOp)
        end,
    safe_operation(WorkerFun, MyState, MoveFullId, [wait_for_change_id], succ, change_id);

% notification from pred/succ that he could not aggree on a slide with us
process_move_msg({move, slide_abort, PredOrSucc, MoveFullId, Reason} = _Msg, State) ->
    ?TRACE1(_Msg, State),
    SlideOp = case PredOrSucc of
                  pred -> dht_node_state:get(State, slide_pred);
                  succ -> dht_node_state:get(State, slide_succ)
              end,
    case SlideOp =/= null andalso slide_op:get_id(SlideOp) =:= MoveFullId of
        true ->
            abort_slide(State, SlideOp, Reason, false);
        _ ->
            log:log(warn, "[ dht_node_move ~.0p ] slide_abort (~.0p) received with no "
                          "matching slide operation (ID: ~.0p, slide_~.0p: ~.0p)~n",
                    [comm:this(), PredOrSucc, MoveFullId, PredOrSucc, SlideOp]),
            State
    end;

% precond: NewNode must have id TargetId
process_move_msg({move, node_update, {move, MoveFullId} = RMSubscrTag} = _Msg, MyState) ->
    ?TRACE1(_Msg, MyState),
    WorkerFun =
        fun(SlideOp, succ, State) ->
                rm_loop:unsubscribe(self(), RMSubscrTag),
                case slide_op:get_sendORreceive(SlideOp) of
                    'send' ->
                        State1 = dht_node_state:add_db_range(
                                   State, slide_op:get_interval(SlideOp)),
                        send_data(State1, succ, SlideOp);
                    'rcv'  -> request_data(State, succ, SlideOp)
                end
        end,
    safe_operation(WorkerFun, MyState, MoveFullId, [wait_for_node_update], succ, node_update);

process_move_msg({move, node_leave} = _Msg, State) ->
    ?TRACE1(_Msg, State),
    % note: can't use safe_operation/6 - there is no slide op id
    SlideOp = dht_node_state:get(State, slide_succ),
    % only handle node_update in wait_for_node_update phase
    case SlideOp =/= null andalso slide_op:is_leave(SlideOp) andalso
             slide_op:get_phase(SlideOp) =:= wait_for_node_update andalso
             slide_op:get_sendORreceive(SlideOp) =:= 'send' of
        true ->
            State1 = dht_node_state:add_db_range(
                       State, slide_op:get_interval(SlideOp)),
            send_data(State1, succ, SlideOp);
        _ ->
            % we should not receive node update messages unless we are waiting for them
            % (node id updates should only be triggered by this module anyway)
            log:log(warn, "[ dht_node_move ~w ] received rm node leave message with no "
                          "matching slide operation (slide_succ: ~w)~n",
                    [comm:this(), SlideOp]),
            State % ignore unrelated node leave messages
    end;

% wait for the joining node to appear in the rm-process -> got ack from rm:
% (see dht_node_join.erl) or
% wait for the rm to update its pred to the expected pred in the data_ack phase
% precond(wait_for_pred_update_join - during join):
%   all conditions to change into the next phase must be met
% precond(wait_for_pred_update_data_ack): none (conditions will be checked here) 
process_move_msg({move, rm_new_pred, {move, MoveFullId} = RMSubscrTag} = _Msg, MyState) ->
    ?TRACE1(_Msg, MyState),
    WorkerFun =
        fun(SlideOp, pred, State) ->
                rm_loop:unsubscribe(self(), RMSubscrTag),
                case slide_op:get_phase(SlideOp) of
                    wait_for_pred_update_join ->
                        NewSlideOp = slide_op:set_phase(SlideOp, wait_for_req_data),
                        dht_node_state:set_slide(State, pred, NewSlideOp);
                    wait_for_pred_update_data_ack ->
                        try_send_delta_to_pred(State, SlideOp)
                end
        end,
    safe_operation(WorkerFun, MyState, MoveFullId, [wait_for_pred_update_join, wait_for_pred_update_data_ack], pred, rm_new_pred);

% timeout waiting for data
process_move_msg({move, rcv_data_timeout, MoveFullId} = _Msg, MyState) ->
    ?TRACE1(_Msg, MyState),
    WorkerFun =
        fun(SlideOp, PredOrSucc, State) ->
                case (slide_op:get_timeouts(SlideOp) < get_rcv_data_retries()) of
                    true ->
                        NewSlideOp = slide_op:inc_timeouts(SlideOp),
                        case PredOrSucc of
                            succ ->
                                request_data(State, succ, NewSlideOp);
                            pred ->
                                notify_other(NewSlideOp, State)
                        end;
                    _ ->
                        abort_slide(State, SlideOp, rcv_data_timeout, true)
                end
        end,
    safe_operation(WorkerFun, MyState, MoveFullId, [wait_for_data], both, rcv_data_timeout);

% request for data from a neighbor
process_move_msg({move, req_data, MoveFullId} = _Msg, MyState) ->
    ?TRACE1(_Msg, MyState),
    WorkerFun =
        fun(SlideOp, PredOrSucc, State) ->
                SlideOp1 = slide_op:reset_timer(SlideOp), % reset previous timeouts
                send_data(State, PredOrSucc, SlideOp1)
        end,
    safe_operation(WorkerFun, MyState, MoveFullId, [wait_for_req_data], pred, req_data);

% request for data from a neighbor
process_move_msg({move, send_data_timeout, MoveFullId} = _Msg, MyState) ->
    ?TRACE1(_Msg, MyState),
    WorkerFun =
        fun(SlideOp, PredOrSucc, State) ->
                case (slide_op:get_timeouts(SlideOp) < get_send_data_retries()) of
                    true ->
                        NewSlideOp = slide_op:inc_timeouts(SlideOp),
                        send_data(State, PredOrSucc, NewSlideOp);
                    _ ->
                        abort_slide(State, SlideOp, send_data_timeout, true)
                end
        end,
    safe_operation(WorkerFun, MyState, MoveFullId, [wait_for_data_ack], both, send_data_timeout);

% data from a neighbor
process_move_msg({move, data, MovingData, MoveFullId} = _Msg, MyState) ->
    ?TRACE1(_Msg, MyState),
    WorkerFun =
        fun(SlideOp, PredOrSucc, State) ->
                SlideOp1 = slide_op:reset_timer(SlideOp), % reset previous timeouts
                accept_data(State, PredOrSucc, SlideOp1, MovingData)
        end,
    safe_operation(WorkerFun, MyState, MoveFullId, [wait_for_data, wait_for_other_mte, wait_for_change_op], both, data);

% request for data from a neighbor
process_move_msg({move, rcv_delta_timeout, MoveFullId} = _Msg, MyState) ->
    ?TRACE1(_Msg, MyState),
    WorkerFun =
        fun(SlideOp, PredOrSucc, State) ->
                case (slide_op:get_timeouts(SlideOp) < get_rcv_delta_retries()) of
                    true ->
                        NewSlideOp = slide_op:inc_timeouts(SlideOp),
                        send_data_ack(State, PredOrSucc, NewSlideOp);
                    _ ->
                        abort_slide(State, SlideOp, rcv_delta_timeout, true)
                end
        end,
    safe_operation(WorkerFun, MyState, MoveFullId, [wait_for_delta], both, rcv_delta_timeout);

% acknowledgement from neighbor that its node received data for the slide op with the given id
process_move_msg({move, data_ack, MoveFullId} = _Msg, MyState) ->
    ?TRACE1(_Msg, MyState),
    WorkerFun =
        fun(SlideOp, PredOrSucc, State) ->
                SlideOp1 = slide_op:reset_timer(SlideOp), % reset previous timeouts
                % if sending data to the predecessor, check if we have already
                % received the new predecessor info, otherwise wait for it
                case PredOrSucc =:= pred andalso
                         slide_op:get_sendORreceive(SlideOp1) =:= send of
                    true -> try_send_delta_to_pred(State, SlideOp1);
                    _    -> send_delta(State, PredOrSucc, SlideOp1)
                end
        end,
    safe_operation(WorkerFun, MyState, MoveFullId, [wait_for_data_ack], both, data_ack);

% request for data from a neighbor
process_move_msg({move, send_delta_timeout, MoveFullId, ChangedData, DeletedKeys} = _Msg, MyState) ->
    ?TRACE1(_Msg, MyState),
    WorkerFun =
        fun(SlideOp, PredOrSucc, State) ->
                case (slide_op:get_timeouts(SlideOp) < get_send_delta_retries()) of
                    true ->
                        NewSlideOp = slide_op:inc_timeouts(SlideOp),
                        send_delta2(State, PredOrSucc, NewSlideOp, ChangedData, DeletedKeys);
                    _ ->
                        % abort slide but no need to tell the other node here
                        abort_slide(State, SlideOp, send_delta_timeout, false)
                end
        end,
    safe_operation(WorkerFun, MyState, MoveFullId, [wait_for_delta_ack], both, send_delta_timeout);

% delta from neighbor
process_move_msg({move, delta, ChangedData, DeletedKeys, MoveFullId} = _Msg, MyState) ->
    ?TRACE1(_Msg, MyState),
    WorkerFun =
        fun(SlideOp, PredOrSucc, State) ->
                SlideOp1 = slide_op:reset_timer(SlideOp), % reset previous timeouts
                accept_delta(State, PredOrSucc, SlideOp1, ChangedData, DeletedKeys)
        end,
    safe_operation(WorkerFun, MyState, MoveFullId, [wait_for_delta], both, delta);

% acknowledgement from neighbor that its node received delta for the slide op
% with the given id and wants to continue the (incremental) slide
process_move_msg({move, delta_ack, MoveFullId, continue, NewSlideId} = _Msg, MyState) ->
    ?TRACE1(_Msg, MyState),
    WorkerFun =
        fun(SlideOp, PredOrSucc, State) ->
                SlideOp1 = slide_op:reset_timer(SlideOp), % reset previous timeouts
                finish_delta_ack_continue(
                  State, PredOrSucc, SlideOp1, NewSlideId)
        end,
    safe_operation(WorkerFun, MyState, MoveFullId, [wait_for_delta_ack], both, delta_ack);

% acknowledgement from neighbor that its node received delta for the slide op
% with the given id and wants to set up a new slide with the given parameters
process_move_msg({move, delta_ack, MoveFullId, OtherNextOpType, NewSlideId, OtherNode,
                  OtherTargetNode, TargetId, Tag, MaxTransportEntries} = _Msg, MyState) ->
    ?TRACE1(_Msg, MyState),
    WorkerFun =
        fun(SlideOp, PredOrSucc, State) ->
                SlideOp1 = slide_op:reset_timer(SlideOp), % reset previous timeouts
                MyNextOpType = slide_op:other_type_to_my_type(OtherNextOpType),
                finish_delta_ack_next(
                  State, PredOrSucc, SlideOp1, MyNextOpType, NewSlideId,
                  OtherTargetNode, OtherNode, TargetId, Tag,
                  MaxTransportEntries, null)
        end,
    safe_operation(WorkerFun, MyState, MoveFullId, [wait_for_delta_ack], both, delta_ack);

% acknowledgement from neighbor that its node received delta for the slide op
% with the given id
process_move_msg({move, delta_ack, MoveFullId} = _Msg, MyState) ->
    ?TRACE1(_Msg, MyState),
    WorkerFun =
        fun(SlideOp, PredOrSucc, State) ->
                SlideOp1 = slide_op:reset_timer(SlideOp), % reset previous timeouts
                finish_delta_ack(State, PredOrSucc, SlideOp1)
        end,
    safe_operation(WorkerFun, MyState, MoveFullId, [wait_for_delta_ack], both, delta_ack).

% misc.

%% @doc Notifies the successor or predecessor about a (new) slide operation and
%%      sets a timeout timer. Assumes that the information in the slide
%%      operation is still correct (check with safe_operation/6!). No timer
%%      should have been set on NewSlideOp. Will also set the appropriate
%%      slide_phase and update the slide op in the dht_node.
-spec notify_other(SlideOp::slide_op:slide_op(), State::dht_node_state:state())
        -> dht_node_state:state().
notify_other(SlideOp, State) ->
    Type = slide_op:get_type(SlideOp),
    PredOrSucc = slide_op:get_predORsucc(Type),
    SlOpNode = slide_op:get_node(SlideOp),
    Phase = slide_op:get_phase(SlideOp),
    SlideOp2 = if Phase =:= wait_for_data andalso PredOrSucc =:= pred ->
                      slide_op:set_timer(
                        SlideOp, get_rcv_data_timeout(),
                        {move, rcv_data_timeout, slide_op:get_id(SlideOp)});
                  true ->
                      slide_op:set_timer(
                        SlideOp, get_notify_other_timeout(),
                        {move, notify_other_timeout, slide_op:get_id(SlideOp)})
               end,
    SetupAtOther = slide_op:is_setup_at_other(SlideOp2),
    SendOrReceive = slide_op:get_sendORreceive(SlideOp2),
    UseIncrSlides = use_incremental_slides(),
    Msg =
        if SetupAtOther ->
               if SendOrReceive =:= 'rcv' andalso PredOrSucc =:= succ andalso
                      Phase =:= wait_for_change_id ->
                      {move, my_mte, slide_op:get_id(SlideOp2), get_max_transport_entries()};
                  SendOrReceive =:= 'rcv' andalso PredOrSucc =:= pred andalso
                      Phase =:= wait_for_change_op ->
                      {move, my_mte, slide_op:get_id(SlideOp2), get_max_transport_entries()};
                  SendOrReceive =:= 'send' andalso PredOrSucc =:= succ ->
                      {move, change_op, slide_op:get_id(SlideOp2),
                       slide_op:get_target_id(SlideOp2),
                       slide_op:get_next_op(SlideOp2)};
                  PredOrSucc =:= pred ->
                      case slide_op:is_incremental(SlideOp2) of
                          true ->
                              {move, change_id, slide_op:get_id(SlideOp2),
                               slide_op:get_target_id(SlideOp2),
                               slide_op:get_next_op(SlideOp2)};
                          _ ->
                              {move, change_id, slide_op:get_id(SlideOp2)}
                      end
               end;
           true ->
               if Phase =:= wait_for_other_mte ->
                      {move, slide_get_mte, Type, slide_op:get_id(SlideOp2),
                       dht_node_state:get(State, node), SlOpNode,
                       slide_op:get_target_id(SlideOp2),
                       slide_op:get_tag(SlideOp2)};
                  true ->
                      case slide_op:is_incremental(SlideOp2) of
                          true ->
                              {move, slide, Type, slide_op:get_id(SlideOp2),
                               dht_node_state:get(State, node), SlOpNode,
                               slide_op:get_target_id(SlideOp2),
                               slide_op:get_tag(SlideOp2),
                               slide_op:get_next_op(SlideOp2)};
                          _ when UseIncrSlides andalso SendOrReceive =:= 'rcv' ->
                              {move, slide_w_mte, Type, slide_op:get_id(SlideOp2),
                               dht_node_state:get(State, node), SlOpNode,
                               slide_op:get_target_id(SlideOp2),
                               slide_op:get_tag(SlideOp2), get_max_transport_entries()};
                          _ ->
                              {move, slide, Type, slide_op:get_id(SlideOp2),
                               dht_node_state:get(State, node), SlOpNode,
                               slide_op:get_target_id(SlideOp2),
                               slide_op:get_tag(SlideOp2)}
                      end
               end
        end,
    ?TRACE_SEND(node:pidX(SlOpNode), Msg),
    comm:send(node:pidX(SlOpNode), Msg),
    dht_node_state:set_slide(State, PredOrSucc, SlideOp2).

%% @doc Sets up a new slide operation with the node's successor or predecessor
%%      after a request for a slide has been received.
-spec setup_slide(State::dht_node_state:state(), Type::slide_op:type(),
                  MoveFullId::slide_op:id(), MyNode::node:node_type(),
                  TargetNode::node:node_type(), TargetId::?RT:key(),
                  Tag::any(), MaxTransportEntries::unknown | pos_integer(),
                  SourcePid::comm:erl_local_pid() | null,
                  MsgTag::nomsg | slide | slide_get_mte | slide_w_mte,
                  NextOp::slide_op:next_op())
        -> dht_node_state:state().
setup_slide(State, Type, MoveFullId, MyNode, TargetNode, TargetId, Tag,
            MaxTransportEntries, SourcePid, MsgTag, NextOp) ->
    case get_slide_op(State, MoveFullId) of
        {ok, _PredOrSucc, _SlideOp} ->
            % there could already be slide operation and a second message was
            % send after a timeout hit on the other node -> ignore this message
            State;
        not_found ->
            Command = check_setup_slide_not_found(
                        State, Type, MyNode, TargetNode, TargetId),
            exec_setup_slide_not_found(
              Command, State, MoveFullId, TargetNode, TargetId, Tag,
              MaxTransportEntries, SourcePid, MsgTag, NextOp);
        {wrong_neighbor, _PredOrSucc, SlideOp} -> % wrong pred or succ
            abort_slide(State, SlideOp, wrong_pred_succ_node, true)
    end.

-type command() :: {abort, abort_reason(), OrigType::slide_op:type()} |
                   {ok, NewType::slide_op:type() | move_done}.

%% @doc Checks whether a new slide operation with the node's successor or
%%      predecessor and the given parameters can be set up.
%%      Note: this does not check whether such a slide already exists.
-spec check_setup_slide_not_found(State::dht_node_state:state(),
        Type::slide_op:type(), MyNode::node:node_type(),
        TargetNode::node:node_type(), TargetId::?RT:key()) -> command().
check_setup_slide_not_found(State, Type, MyNode, TNode, TId) ->
    PredOrSucc = slide_op:get_predORsucc(Type),
    CanSlide = case PredOrSucc of
                   pred -> can_slide_pred(State, TId, Type);
                   succ -> can_slide_succ(State, TId, Type)
               end,
    % correct pred/succ info? did pred/succ know our current ID (compare node info)
    NodesCorrect = MyNode =:= dht_node_state:get(State, node) andalso
                       TNode =:= dht_node_state:get(State, PredOrSucc),
    MoveDone = (PredOrSucc =:= pred andalso node:id(TNode) =:= TId) orelse
               (PredOrSucc =:= succ andalso node:id(MyNode) =:= TId),
    case CanSlide andalso NodesCorrect andalso not MoveDone of
        true ->
            case slide_op:is_leave(Type, 'send') of
                true ->
                    % graceful leave (slide with succ, send all data)
                    % note: may also be a jump operation!
                    % TODO: check for running slide, abort it if possible, eventually extend it
                    case slide_op:is_jump(Type) of
                        true ->
                            TIdInRange = dht_node_state:is_responsible(
                                                TId, State),
                            TIdInSuccRange =
                                intervals:in(TId,
                                             dht_node_state:get(State, succ_range)),
                            if % convert jump to slide?
                                TIdInRange     -> {ok, {slide, succ, 'send'}};
                                TIdInSuccRange -> {ok, {slide, succ, 'rcv'}};
                                true ->
                                    SlideSucc =
                                        dht_node_state:get(State, slide_succ),
                                    SlidePred =
                                        dht_node_state:get(State, slide_pred),
                                    case SlideSucc =/= null andalso
                                             SlidePred =/= null of
                                        true -> {ok, {jump, 'send'}};
                                        _    -> {abort, ongoing_slide, Type}
                                    end
                            end;
                        _ -> {ok, {leave, 'send'}}
                    end;
                _ ->
                    TIdInRange = dht_node_state:is_responsible(TId, State),
                    SendOrReceive = slide_op:get_sendORreceive(Type),
                    case SendOrReceive =:= 'send' andalso not TIdInRange of
                        true -> {abort, target_id_not_in_range, Type};
                        _    -> {ok, {slide, PredOrSucc, SendOrReceive}}
                    end
            end;
        _ when not CanSlide -> {abort, ongoing_slide, Type};
        _ when not NodesCorrect -> {abort, wrong_pred_succ_node, Type};
        _ -> {ok, move_done} % MoveDone, i.e. target id already reached (noop)
    end.

%% @doc Creates a new slide operation with the node's successor or
%%      predecessor and the given parameters according to the command created
%%      by check_setup_slide_not_found/5.
%%      Note: assumes that such a slide does not already exist.
-spec exec_setup_slide_not_found(
        Command::command(), State::dht_node_state:state(),
        MoveFullId::slide_op:id(), TargetNode::node:node_type(),
        TargetId::?RT:key(), Tag::any(),
        OtherMaxTransportEntries::unknown | pos_integer(),
        SourcePid::comm:erl_local_pid() | null,
        MsgTag::nomsg | slide | slide_get_mte | slide_w_mte | delta_ack | change_id | my_mte,
        NextOp::slide_op:next_op()) -> dht_node_state:state().
exec_setup_slide_not_found(Command, State, MoveFullId, TargetNode,
                           TargetId, Tag, OtherMTE, SourcePid, MsgTag, NextOp) ->
    % note: NewType (inside the command) may be different than the initially planned type
    case Command of
        {abort, Reason, OrigType} ->
            abort_slide(State, TargetNode, MoveFullId, null, SourcePid, Tag,
                        OrigType, Reason, MsgTag =/= nomsg);
        {ok, {jump, 'send'}} -> % similar to {ok, slide, succ, 'send'}
            % TODO: activate incremental jump:
%%             IncTargetKey = find_incremental_target_id(State, TargetId, NewType, OtherMTE),
%%             SlideOp = slide_op:new_sending_slide_jump(MoveFullId, IncTargetKey, TargetId, Tag, State),
            SlideOp = slide_op:new_sending_slide_jump(MoveFullId, TargetId, Tag, State),
            case MsgTag of
                nomsg ->
                    SlideOp1 = slide_op:set_phase(SlideOp, wait_for_change_id),
                    notify_other(SlideOp1, State);
                _ -> change_my_id(State, SlideOp)
            end;
        {ok, {leave, 'send'}} -> % similar to {ok, slide, succ, 'send'}
            % TODO: activate incremental leave:
%%             IncTargetKey = find_incremental_target_id(State, TargetId, NewType, OtherMTE),
%%             SlideOp = slide_op:new_sending_slide_leave(MoveFullId, IncTargetKey, leave, State),
            SlideOp = slide_op:new_sending_slide_leave(MoveFullId, leave, State),
            case MsgTag of
                nomsg ->
                    SlideOp1 = slide_op:set_phase(SlideOp, wait_for_change_id),
                    notify_other(SlideOp1, State);
                _ -> change_my_id(State, SlideOp)
            end;
        % send data to pred:
        {ok, {slide, pred, 'send'} = NewType} ->
            % slide with pred, send data
            UseIncrSlides = use_incremental_slides(),
            UseSymmIncrSlides = use_symmetric_incremental_slides(),
            case MsgTag of
                nomsg when not UseIncrSlides ->
                    SlideOp = slide_op:new_slide(
                                MoveFullId, NewType, TargetId, Tag, SourcePid,
                                OtherMTE, NextOp, State),
                    SlideOp1 = slide_op:set_phase(SlideOp, wait_for_req_data),
                    State1 = dht_node_state:add_db_range(State, slide_op:get_interval(SlideOp1)),
                    notify_other(SlideOp1, State1);
                nomsg when UseSymmIncrSlides ->
                    IncTargetKey = find_incremental_target_id(
                                     State, TargetId, NewType, OtherMTE),
                    SlideOp = slide_op:new_slide_i(
                                MoveFullId, NewType, IncTargetKey, TargetId,
                                Tag, SourcePid, OtherMTE, State),
                    SlideOp1 = slide_op:set_phase(SlideOp, wait_for_req_data),
                    State1 = dht_node_state:add_db_range(State, slide_op:get_interval(SlideOp1)),
                    notify_other(SlideOp1, State1);
                nomsg -> % asymmetric slide -> get mte:
                    % note: can not add db range yet (current range unknown)
                    SlideOp = slide_op:new_slide(
                                MoveFullId, NewType, TargetId, Tag, SourcePid,
                                OtherMTE, NextOp, State),
                    SlideOp1 = slide_op:set_phase(SlideOp, wait_for_other_mte),
                    notify_other(SlideOp1, State);
                X when (X =:= slide orelse X =:= slide_w_mte orelse
                            X =:= delta_ack) andalso not UseIncrSlides ->
                    SlideOp = slide_op:new_slide(
                                MoveFullId, NewType, TargetId, Tag, SourcePid,
                                OtherMTE, NextOp, State),
                    SlideOp1 = slide_op:set_phase(SlideOp, wait_for_req_data),
                    SlideOp2 = slide_op:set_setup_at_other(SlideOp1),
                    State1 = dht_node_state:add_db_range(State, slide_op:get_interval(SlideOp2)),
                    notify_other(SlideOp2, State1);
                Y when (Y =:= slide orelse Y =:= slide_w_mte orelse
                            Y =:= delta_ack orelse Y =:= my_mte) ->
                    IncTargetKey = find_incremental_target_id(
                                     State, TargetId, NewType, OtherMTE),
                    SlideOp = slide_op:new_slide_i(
                                MoveFullId, NewType, IncTargetKey, TargetId,
                                Tag, SourcePid, OtherMTE, State),
                    SlideOp1 = slide_op:set_phase(SlideOp, wait_for_req_data),
                    SlideOp2 = slide_op:set_setup_at_other(SlideOp1),
                    State1 = dht_node_state:add_db_range(State, slide_op:get_interval(SlideOp2)),
                    notify_other(SlideOp2, State1)
            end;
        {ok, {slide, succ, 'rcv'} = NewType} ->
            % slide with succ, receive data
            SlideOp = slide_op:new_slide(MoveFullId, NewType, TargetId, Tag,
                                         SourcePid, OtherMTE, NextOp, State),
            case MsgTag of
                nomsg ->
                    SlideOp2 = slide_op:set_phase(SlideOp, wait_for_change_id),
                    notify_other(SlideOp2, State);
                slide_get_mte -> % send MTE to other node
                    SlideOp2 = slide_op:set_phase(SlideOp, wait_for_change_id),
                    SlideOp3 = slide_op:set_setup_at_other(SlideOp2),
                    notify_other(SlideOp3, State);
                _ ->
                    change_my_id(State, SlideOp)
            end;
        % send data to succ:
        {ok, {slide, succ, 'send'} = NewType} ->
            % slide with succ, send data
            UseIncrSlides = use_incremental_slides(),
            UseSymmIncrSlides = use_symmetric_incremental_slides(),
            case MsgTag of
                nomsg when not UseIncrSlides ->
                    SlideOp = slide_op:new_slide(
                                MoveFullId, NewType, TargetId, Tag, SourcePid,
                                OtherMTE, NextOp, State),
                    SlideOp1 = slide_op:set_phase(SlideOp, wait_for_change_id),
                    notify_other(SlideOp1, State);
                nomsg when UseSymmIncrSlides ->
                    IncTargetKey = find_incremental_target_id(
                                     State, TargetId, NewType,
                                     get_max_transport_entries()),
                    SlideOp = slide_op:new_slide_i(
                                MoveFullId, NewType, IncTargetKey, TargetId,
                                Tag, SourcePid, OtherMTE, State),
                    SlideOp1 = slide_op:set_phase(SlideOp, wait_for_change_id),
                    notify_other(SlideOp1, State);
                nomsg -> % asymmetric slide -> get mte:
                    SlideOp = slide_op:new_slide(
                                MoveFullId, NewType, TargetId, Tag, SourcePid,
                                OtherMTE, NextOp, State),
                    SlideOp1 = slide_op:set_phase(SlideOp, wait_for_other_mte),
                    notify_other(SlideOp1, State);
                slide ->
                    % note: even we wanted to do an incremental slide, the
                    % other has already set up a msg forward
                    SlideOp = slide_op:new_slide(
                                MoveFullId, NewType, TargetId, Tag, SourcePid,
                                OtherMTE, NextOp, State),
                    change_my_id(State, SlideOp);
                change_id ->
                    SlideOp = slide_op:new_slide(
                                MoveFullId, NewType, TargetId, Tag, SourcePid,
                                OtherMTE, NextOp, State),
                    change_my_id(State, SlideOp);
                X when (X =:= slide_w_mte orelse X =:= my_mte orelse X =:= delta_ack) ->
                    IncTargetKey = find_incremental_target_id(
                                     State, TargetId, NewType, OtherMTE),
                    SlideOp = slide_op:new_slide_i(
                                MoveFullId, NewType, IncTargetKey, TargetId,
                                Tag, SourcePid, OtherMTE, State),
                    SlideOp1 = slide_op:set_phase(SlideOp, wait_for_change_id),
                    SlideOp2 = slide_op:set_setup_at_other(SlideOp1),
                    notify_other(SlideOp2, State)
            end;
        {ok, {slide, pred, 'rcv'} = NewType} ->
            % slide with pred, receive data
            SlideOp = slide_op:new_slide(MoveFullId, NewType, TargetId, Tag,
                                         SourcePid, OtherMTE, NextOp, State),
            UseIncrSlides = use_incremental_slides(),
            case MsgTag of
                nomsg when not UseIncrSlides ->
                    State1 = dht_node_state:add_msg_fwd(
                               State, slide_op:get_interval(SlideOp),
                               node:pidX(slide_op:get_node(SlideOp))),
                    SlideOp1 = slide_op:set_phase(SlideOp, wait_for_data),
                    notify_other(SlideOp1, State1);
                nomsg ->
                    % we can not add msg forward yet as we do not know our target id
                    SlideOp1 = slide_op:set_phase(SlideOp, wait_for_change_op),
                    notify_other(SlideOp1, State);
                slide_get_mte ->
                    % we can not add msg forward yet as we do not know our target id
                    SlideOp1 = slide_op:set_phase(SlideOp, wait_for_change_op),
                    SlideOp2 = slide_op:set_setup_at_other(SlideOp1),
                    notify_other(SlideOp2, State);
                X when (X =:= slide orelse X =:= change_op) ->
                    SlideOp1 = slide_op:set_phase(SlideOp, wait_for_data),
                    SlideOp2 = slide_op:set_setup_at_other(SlideOp1),
                    State1 = dht_node_state:add_msg_fwd(
                               State, slide_op:get_interval(SlideOp2),
                               node:pidX(slide_op:get_node(SlideOp2))),
                    notify_other(SlideOp2, State1)
            end;
        {ok, move_done} ->
            notify_source_pid(SourcePid, {move, result, Tag, ok}),
            case MsgTag of
                nomsg -> ok;
                _     -> Msg = {move, done, MoveFullId},
                         ?TRACE_SEND(node:pidX(TargetNode), Msg),
                         comm:send(node:pidX(TargetNode), Msg)
            end,
            State
    end.

%% @doc On the sending node: looks into the DB and selects a key in the slide
%%      op's range which involves at most OtherMaxTransportEntries DB entries
%%      to be moved.
-spec find_incremental_target_id(State::dht_node_state:state(),
        FinalTargetId::?RT:key(), Type::slide_op:type(),
        OtherMaxTransportEntries::unknown | pos_integer()) -> ?RT:key().
find_incremental_target_id(State, FinalTargetId, Type, OtherMTE) ->
    PredOrSucc = slide_op:get_predORsucc(Type),
    SendOrReceive = slide_op:get_sendORreceive(Type),
    MTE = case OtherMTE of
              unknown -> get_max_transport_entries();
              _       -> erlang:min(OtherMTE, get_max_transport_entries())
          end,
    % if data is send to the successor, we need to increase the MTE since the
    % last found item will be left on this node
    MTE1 = if PredOrSucc =:= succ andalso SendOrReceive =:= 'send' -> MTE + 1;
              true -> MTE
           end,
    DB = dht_node_state:get(State, db),
    PredId = dht_node_state:get(State, pred_id),
    % TODO: optimise here - if the remaining interval has no data, return FinalTargetId
    try case PredOrSucc of
            pred ->
                {SplitKey, _} = ?DB:get_split_key(DB, PredId, MTE1, forward),
                % beware not to select a key larger than TargetId:
                case nodelist:succ_ord_id(SplitKey, FinalTargetId, PredId) of
                    true -> SplitKey;
                    _    -> FinalTargetId
                end;
            succ ->
                MyId = dht_node_state:get(State, node_id),
                {SplitKey, _} = ?DB:get_split_key(DB, MyId, MTE1, backward),
                % beware not to select a key smaller than TargetId:
                case nodelist:succ_ord_id(SplitKey, FinalTargetId, PredId) of
                    true -> FinalTargetId;
                    _    -> SplitKey
                end
        end
    catch
        throw:empty_db -> FinalTargetId
    end.

%% @doc Change the local node's ID to the given TargetId by calling the ring
%%      maintenance and changing the slide operation's phase to
%%      wait_for_node_update. 
-spec change_my_id(State::dht_node_state:state(), SlideOp::slide_op:slide_op())
        -> dht_node_state:state().
change_my_id(State, SlideOp) ->
    SlideOp1 = slide_op:set_setup_at_other(SlideOp),
    State1 = case slide_op:get_sendORreceive(SlideOp1) of
                 'send' -> dht_node_state:add_db_range(
                             State, slide_op:get_interval(SlideOp1));
                 'rcv'  -> dht_node_state:add_msg_fwd(
                             State, slide_op:get_interval(SlideOp1),
                             node:pidX(slide_op:get_node(SlideOp1)))
             end,
    case slide_op:is_leave(SlideOp1) of
        true ->
            rm_loop:leave(),
            % de-activate processes not needed anymore:
            dht_node_reregister:deactivate(),
            % note: do not deactivate gossip, vivaldi or dc_clustering -
            % their values are still valid and still count!
%%             gossip:deactivate(),
%%             dc_clustering:deactivate(),
%%             vivaldi:deactivate(),
            cyclon:deactivate(),
            rt_loop:deactivate(),
            dht_node_state:set_slide(
              State1, succ, slide_op:set_phase(SlideOp1, wait_for_node_update));
        _ ->
            % note: subscribe with fully qualified function names, i.e. module:fun/arity
            % (a so created fun seems to be the same no matter where created)
            TargetId = slide_op:get_target_id(SlideOp1),
            RMSubscrTag = {move, slide_op:get_id(SlideOp1)},
            rm_loop:subscribe(self(), RMSubscrTag,
                              fun(_OldNeighbors, NewNeighbors) ->
                                      nodelist:nodeid(NewNeighbors) =:= TargetId
                                      % note: no need to check the id version
                              end,
                              fun dht_node_move:rm_send_node_change/4, 1),
            rm_loop:update_id(TargetId),
            dht_node_state:set_slide(
              State1, succ, slide_op:set_phase(SlideOp1, wait_for_node_update))
    end.

%% @doc Requests data from the node of the given slide operation, sets a
%%      rcv_data_timeout timeout, sets the slide operation's phase to
%%      wait_for_data and sets the slide operation in the dht node's state.
-spec request_data(State::dht_node_state:state(), PredOrSucc::succ, SlideOp::slide_op:slide_op()) -> dht_node_state:state().
request_data(State, PredOrSucc = succ, SlideOp) ->
    SlOp1 = slide_op:set_timer(SlideOp, get_rcv_data_timeout(),
                              {move, rcv_data_timeout, slide_op:get_id(SlideOp)}),
    NewSlideOp = slide_op:set_phase(SlOp1, wait_for_data),
    Msg = {move, req_data, slide_op:get_id(NewSlideOp)},
    ?TRACE_SEND(node:pidX(slide_op:get_node(NewSlideOp)), Msg),
    comm:send(node:pidX(slide_op:get_node(NewSlideOp)), Msg),
    dht_node_state:set_slide(State, PredOrSucc, NewSlideOp).

%% @doc Gets all data in the slide operation's interval from the DB and sends
%%      it to the target node. Also sets the DB to record changes in this
%%      interval, changes the slide operation's phase to wait_for_data_ack and
%%      sets a send_data_timeout.
-spec send_data(State::dht_node_state:state(), PredOrSucc::pred | succ, SlideOp::slide_op:slide_op()) -> dht_node_state:state().
send_data(State, PredOrSucc, SlideOp) ->
    MovingInterval = slide_op:get_interval(SlideOp),
    OldDB = dht_node_state:get(State, db),
    MovingData = ?DB:get_entries(OldDB, MovingInterval),
    NewDB = ?DB:record_changes(OldDB, MovingInterval),
    SlOp2 = slide_op:set_timer(SlideOp, get_send_data_timeout(),
                              {move, send_data_timeout, slide_op:get_id(SlideOp)}),
    Msg = {move, data, MovingData, slide_op:get_id(SlOp2)},
    ?TRACE_SEND(node:pidX(slide_op:get_node(SlOp2)), Msg),
    comm:send(node:pidX(slide_op:get_node(SlOp2)), Msg),
    NewSlideOp = slide_op:set_phase(SlOp2, wait_for_data_ack),
    State_NewDB = dht_node_state:set_db(State, NewDB),
    dht_node_state:set_slide(State_NewDB, PredOrSucc, NewSlideOp).

%% @doc Accepts data received during the given (existing!) slide operation and
%%      writes it to the DB. Then calls send_data_ack/3.
%% @see send_data_ack/3
-spec accept_data(State::dht_node_state:state(), PredOrSucc::pred | succ,
                  SlideOp::slide_op:slide_op(), Data::?DB:db_as_list()) -> dht_node_state:state().
accept_data(State, PredOrSucc, SlideOp, Data) ->
    NewDB = ?DB:add_data(dht_node_state:get(State, db), Data),
    State1 = dht_node_state:set_db(State, NewDB),
    send_data_ack(State1, PredOrSucc, SlideOp).

%% @doc Sets a data_ack message for the given slide operation, sets its phase
%%      to wait_for_delta and sets a rcv_delta_timeout timeout.
-spec send_data_ack(State::dht_node_state:state(), PredOrSucc::pred | succ, SlideOp::slide_op:slide_op()) -> dht_node_state:state().
send_data_ack(State, PredOrSucc, SlideOp) ->
    SlOp1 = slide_op:set_timer(SlideOp, get_rcv_delta_timeout(),
                              {move, rcv_delta_timeout, slide_op:get_id(SlideOp)}),
    NewSlideOp = slide_op:set_phase(SlOp1, wait_for_delta),
    Msg = {move, data_ack, slide_op:get_id(NewSlideOp)},
    ?TRACE_SEND(node:pidX(slide_op:get_node(NewSlideOp)), Msg),
    comm:send(node:pidX(slide_op:get_node(NewSlideOp)), Msg),
    dht_node_state:set_slide(State, PredOrSucc, NewSlideOp).

%% @doc Tries to send the delta to the predecessor. If a slide is sending
%%      data to its predecessor, we need to take care that the delta is not
%%      send before the predecessor has changed its ID and our node knows
%%      about it.
-spec try_send_delta_to_pred(State::dht_node_state:state(), SlideOp::slide_op:slide_op()) -> dht_node_state:state().
try_send_delta_to_pred(State, SlideOp) ->
    ExpPredId = slide_op:get_target_id(SlideOp),
    Pred = dht_node_state:get(State, pred),
    case node:id(Pred) of
        ExpPredId ->
            send_delta(State, pred, SlideOp);
        _ ->
            SlideOp1 = slide_op:set_phase(SlideOp, wait_for_pred_update_data_ack),
            rm_subscribe_to_pred_change(SlideOp1),
            dht_node_state:set_slide(State, pred, SlideOp1)
    end.

%% @doc Gets changed data in the slide operation's interval from the DB and
%%      sends as a delta to the target node. Also sets the DB to stop recording
%%      changes in this interval and delete any such entries. Changes the slide
%%      operation's phase to wait_for_delta_ack and calls send_delta2/5.
%% @see send_delta2/5
-spec send_delta(State::dht_node_state:state(), PredOrSucc::pred | succ, SlideOp::slide_op:slide_op()) -> dht_node_state:state().
send_delta(State, PredOrSucc, SlideOp) ->
    SlideOpInterval = slide_op:get_interval(SlideOp),
    % send delta (values of keys that have changed during the move)
    OldDB = dht_node_state:get(State, db),
    {ChangedData, DeletedKeys} = ?DB:get_changes(OldDB, SlideOpInterval),
    NewDB1 = ?DB:stop_record_changes(OldDB, SlideOpInterval),
    NewDB = ?DB:delete_entries(NewDB1, SlideOpInterval),
    State1 = dht_node_state:set_db(State, NewDB),
    State2 = dht_node_state:rm_db_range(State1, SlideOpInterval),
    SlOp1 = slide_op:set_phase(SlideOp, wait_for_delta_ack),
    send_delta2(State2, PredOrSucc, SlOp1, ChangedData, DeletedKeys).

%% @doc Sets a delta message with the given data and sets a send_delta_timeout
%%      timeout.
-spec send_delta2(State::dht_node_state:state(), PredOrSucc::pred | succ, SlideOp::slide_op:slide_op(), ChangedData::?DB:db_as_list(), DeletedKeys::[?RT:key()]) -> dht_node_state:state().
send_delta2(State, PredOrSucc, SlideOp, ChangedData, DeletedKeys) ->
    SlOp1 = slide_op:set_timer(SlideOp, get_send_delta_timeout(),
                              {move, send_delta_timeout, slide_op:get_id(SlideOp),
                               ChangedData, DeletedKeys}),
    Msg = {move, delta, ChangedData, DeletedKeys, slide_op:get_id(SlOp1)},
    ?TRACE_SEND(node:pidX(slide_op:get_node(SlOp1)), Msg),
    comm:send(node:pidX(slide_op:get_node(SlOp1)), Msg),
    dht_node_state:set_slide(State, PredOrSucc, SlOp1).

%% @doc Accepts delta received during the given (existing!) slide operation and
%%      writes it to the DB. Then removes the dht_node's message forward for 
%%      the slide operation's interval, sends a delta_ack message, notifies
%%      the source pid (if it exists) and removes the slide operation from the
%%      dht_node_state.
-spec accept_delta(State::dht_node_state:state(), PredOrSucc::pred | succ,
                   SlideOp::slide_op:slide_op(), ChangedData::?DB:db_as_list(),
                   DeletedKeys::[?RT:key()]) -> dht_node_state:state().
accept_delta(State, PredOrSucc, SlideOp, ChangedData, DeletedKeys) ->
    NewDB1 = ?DB:add_data(dht_node_state:get(State, db), ChangedData),
    NewDB2 = ?DB:delete_entries(NewDB1, intervals:from_elements(DeletedKeys)),
    State1 = dht_node_state:set_db(State, NewDB2),
    State2 = dht_node_state:rm_msg_fwd(
               State1, slide_op:get_interval(SlideOp)),

    % continue with the next planned operation:
    case slide_op:is_incremental(SlideOp) of
        true -> continue_slide_delta(State2, PredOrSucc, SlideOp);
        _ ->
            case slide_op:get_next_op(SlideOp) of
                {none} -> accept_delta2(State2, PredOrSucc, SlideOp);
                {join, _NewTargetId} ->
                    log:log(warn, "[ dht_node_move ~.0p ] ignoring scheduled join after "
                                  "receiving data (this doesn't make any sense!)",
                            [comm:this()]),
                    accept_delta2(State2, PredOrSucc, SlideOp);
                {slide, PredOrSucc, NewTargetId, NewTag, NewSourcePid} ->
                    % continue operation with the same node previously sliding with
                    % TODO: piggy-back slide setup information with delta_ack
                    % {move, delta_ack, MoveFullId::slide_op:id(), OtherType::slide_op:type(), NewSlideId::slide_op:id(), InitNode::node:node_type(), TargetNode::node:node_type(), TargetId::?RT:key(), Tag::any(), MaxTransportEntries::pos_integer()} |
                    State3 = accept_delta2(State2, PredOrSucc, SlideOp),
                    make_slide(State3, PredOrSucc, NewTargetId, NewTag, NewSourcePid);
                {slide, PredOrSucc2, NewTargetId, NewTag, NewSourcePid} ->
                    % try setting up a slide with the other node
                    State4 = accept_delta2(State2, PredOrSucc, SlideOp),
                    make_slide(State4, PredOrSucc2, NewTargetId, NewTag, NewSourcePid);
                {jump, NewTargetId, NewTag, NewSourcePid} ->
                    % finish current slide, then set up jump
                    % TODO: piggy-back slide setup information with delta_ack (if possible)
                    State5 = accept_delta2(State2, PredOrSucc, SlideOp),
                    make_jump(State5, NewTargetId, NewTag, NewSourcePid);
                {leave} ->
                    % finish current slide, then set up leave
                    % (this is not a continued operation!)
                    State6 = accept_delta2(State2, PredOrSucc, SlideOp),
                    make_slide_leave(State6)
            end
    end.

-spec accept_delta2(State::dht_node_state:state(), PredOrSucc::pred | succ,
                    SlideOp::slide_op:slide_op()) -> dht_node_state:state().
accept_delta2(State, PredOrSucc, SlideOp) ->
    Msg = {move, delta_ack, slide_op:get_id(SlideOp)},
    ?TRACE_SEND(node:pidX(slide_op:get_node(SlideOp)), Msg),
    comm:send(node:pidX(slide_op:get_node(SlideOp)), Msg),
    notify_source_pid(slide_op:get_source_pid(SlideOp),
                      {move, result, slide_op:get_tag(SlideOp), ok}),
    dht_node_state:set_slide(State, PredOrSucc, null).

continue_slide_delta(State, PredOrSucc, SlideOp) ->
    Type = slide_op:get_type(SlideOp),
    % TODO: support other types
    case slide_op:get_next_op(SlideOp) of
        {slide, continue, NewTargetId} when Type =:= {slide, PredOrSucc, 'rcv'} ->
            State1 = dht_node_state:set_slide(State, PredOrSucc, null),
            MyNode = dht_node_state:get(State1, node),
            TargetNode = dht_node_state:get(State1, PredOrSucc),
            MoveFullId = slide_op:get_id(SlideOp),
            Tag = slide_op:get_tag(SlideOp),
            SourcePid = slide_op:get_source_pid(SlideOp),
            OtherMTE = slide_op:get_other_max_entries(SlideOp),
            Command = check_setup_slide_not_found(
                        State1, Type, MyNode, TargetNode, NewTargetId),
            case Command of
                {ok, {slide, _, 'rcv'} = NewType} ->
                    % continued slide with pred/succ, receive data
                    % -> reserve slide_op with pred/succ
                    NextSlideOp =
                        slide_op:new_slide(util:get_global_uid(), NewType,
                                           NewTargetId, Tag, SourcePid,
                                           OtherMTE, {none}, State1),
                    NextSlideOp1 =
                        case slide_op:get_predORsucc(NextSlideOp) of
                            pred ->
                                slide_op:set_phase(NextSlideOp, wait_for_change_op);
                            succ ->
                                slide_op:set_phase(NextSlideOp, wait_for_change_id)
                        end,
                    notify_other_in_delta_ack(MoveFullId, NextSlideOp1, State1);
                {abort, Reason, _Type} -> % note: the type returned here is the same as Type 
                    abort_slide(State1, TargetNode, MoveFullId, null, SourcePid, Tag,
                                Type, Reason, true)
            end;
        {jump, continue, NewTargetId} ->
            % TODO
            accept_delta2(State, PredOrSucc, SlideOp);
        {leave, continue} ->
            % TODO
            accept_delta2(State, PredOrSucc, SlideOp)
    end.

% similar to notify_other/2:
% pre: incremental slide in slide op on this node
-spec notify_other_in_delta_ack(OldMoveFullId::slide_op:id(),
        NextSlideOp::slide_op:slide_op(), State::dht_node_state:state())
            -> dht_node_state:state().
notify_other_in_delta_ack(OldMoveFullId, NextSlideOp, State) ->
    NextSlideOp2 = slide_op:set_timer(
                 NextSlideOp, get_notify_other_timeout(),
                 {move, notify_other_continue_timeout, OldMoveFullId,
                  slide_op:get_id(NextSlideOp)}),
    Msg = {move, delta_ack, OldMoveFullId, continue,
           slide_op:get_id(NextSlideOp2)},
    ?TRACE_SEND(node:pidX(slide_op:get_node(NextSlideOp2)), Msg),
    comm:send(node:pidX(slide_op:get_node(NextSlideOp2)), Msg),
    PredOrSucc = slide_op:get_predORsucc(NextSlideOp2),
    dht_node_state:set_slide(State, PredOrSucc, NextSlideOp2).

-spec finish_delta_ack(State::dht_node_state:state(), PredOrSucc::pred | succ,
                       SlideOp::slide_op:slide_op()) -> dht_node_state:state().
finish_delta_ack(State, PredOrSucc, SlideOp) ->
    notify_source_pid(slide_op:get_source_pid(SlideOp),
                      {move, result, slide_op:get_tag(SlideOp), ok}),
    case slide_op:is_leave(SlideOp) andalso not slide_op:is_jump(SlideOp) of
        true ->
            SupDhtNodeId = erlang:get(my_sup_dht_node_id),
            ok = supervisor:terminate_child(main_sup, SupDhtNodeId),
            ok = supervisor:delete_child(main_sup, SupDhtNodeId),
            kill;
        _    ->
            State1 = dht_node_state:set_slide(State, PredOrSucc, null),
            % continue with the next planned operation:
            case slide_op:get_next_op(SlideOp) of
                {none} -> State1;
                {join, NewTargetId} ->
                    OldIdVersion = node:id_version(dht_node_state:get(State1, node)),
                    dht_node_join:join_as_other(NewTargetId, OldIdVersion + 1, [{skip_psv_lb}]);
                {slide, PredOrSucc, NewTargetId, NewTag, NewSourcePid} ->
                    make_slide(State1, PredOrSucc, NewTargetId, NewTag, NewSourcePid);
                {jump, NewTargetId, NewTag, NewSourcePid} ->
                    make_jump(State1, NewTargetId, NewTag, NewSourcePid);
                {leave} ->
                    make_slide_leave(State1)
            end
    end.

-spec finish_delta_ack_continue(
        State::dht_node_state:state(), PredOrSucc::pred | succ,
        SlideOp::slide_op:slide_op(), NewSlideId::slide_op:id())
    -> dht_node_state:state().
finish_delta_ack_continue(State, PredOrSucc, SlideOp, NewSlideId) ->
    MyNode = dht_node_state:get(State, node),
    TargetNode = dht_node_state:get(State, PredOrSucc),
    Tag = slide_op:get_tag(SlideOp),
    SourcePid = slide_op:get_source_pid(SlideOp),
    Type = slide_op:get_type(SlideOp),
    OtherMTE = slide_op:get_other_max_entries(SlideOp),
    % TODO: support other types
    case slide_op:get_next_op(SlideOp) of
        {slide, continue, NewTargetId} when Type =:= {slide, PredOrSucc, 'send'} ->
            finish_delta_ack_next(
              State, PredOrSucc, SlideOp, Type, NewSlideId, MyNode,
              TargetNode, NewTargetId, Tag, OtherMTE, SourcePid);
        {jump, continue, NewTargetId} ->
            % TODO
            finish_delta_ack(State, PredOrSucc, SlideOp);
        {leave, continue} ->
            % TODO
            finish_delta_ack(State, PredOrSucc, SlideOp);
        _ -> % our next op is different from the other node's next op
            % TODO
            abort_slide(State, SlideOp, next_op_mismatch, true)
    end.

-spec finish_delta_ack_next(
        State::dht_node_state:state(), PredOrSucc::pred | succ,
        SlideOp::slide_op:slide_op(), MyNextOpType::slide_op:type(),
        NewSlideId::slide_op:id(), MyNode::node:node_type(),
        TargetNode::node:node_type(), TargetId::?RT:key(), Tag::any(),
        MaxTransportEntries::pos_integer(),
        SourcePid::comm:erl_local_pid() | null) -> dht_node_state:state().
finish_delta_ack_next(State, PredOrSucc, SlideOp, MyNextOpType, NewSlideId,
                      MyNode, TargetNode, TargetId, Tag, MaxTransportEntries,
                      SourcePid) ->
    case slide_op:is_leave(SlideOp) andalso not slide_op:is_jump(SlideOp) of
        true ->
            % TODO: allow if continue op is leave, too!
            log:log(warn, "[ dht_node_move ~.0p ] ignoring request to continue "
                          "a leave operation (this doesn't make any sense!)",
                    [comm:this()]),
            SupDhtNodeId = erlang:get(my_sup_dht_node_id),
            ok = supervisor:terminate_child(main_sup, SupDhtNodeId),
            ok = supervisor:delete_child(main_sup, SupDhtNodeId),
            kill;
        _    ->
            % Always prefer the other node's next_op over ours as it is almost
            % set up. Unless our scheduled op is a leave operation which needs
            % to be favoured.
            case slide_op:get_next_op(SlideOp) of
                {leave} ->
                    State1 = abort_slide(State, SlideOp, scheduled_leave, true),
                    make_slide_leave(State1);
                MyNextOp ->
                    % TODO: check if warnings are generated in all cases
                    case MyNextOp of
                        {none} -> ok;
                        {slide, continue, TargetId} -> ok;
                        {jump, continue, TargetId} -> ok;
                        {leave, continue} -> ok;
                        _ ->
                            log:log(info, "[ dht_node_move ~.0p ] removing "
                                          "scheduled next op ~.0p, "
                                          "got next op: ~.0p",
                                    [comm:this(), MyNextOp, MyNextOpType])
                    end,
                    State1 = dht_node_state:set_slide(State, PredOrSucc, null),
                    Cmd = check_setup_slide_not_found(
                            State1, MyNextOpType, MyNode, TargetNode, TargetId),
                    exec_setup_slide_not_found(
                      Cmd, State1, NewSlideId, TargetNode, TargetId,
                      Tag, MaxTransportEntries, SourcePid, delta_ack, {none})
            end
    end.

%% @doc Checks if a slide operation with the given MoveFullId exists and
%%      executes WorkerFun if everything is ok. If the successor/predecessor
%%      information in the slide operation is incorrect, the slide is aborted
%%      (a message to the pred/succ is send, too).
-spec safe_operation(
    WorkerFun::fun((SlideOp::slide_op:slide_op(), PredOrSucc::pred | succ,
                    State::dht_node_state:state()) -> dht_node_state:state()),
    State::dht_node_state:state(), MoveFullId::slide_op:id(),
    WorkPhases::[slide_op:phase(),...], PredOrSuccExp::pred | succ | both,
    MoveMsgTag::atom()) -> dht_node_state:state().
safe_operation(WorkerFun, State, MoveFullId, WorkPhases, PredOrSuccExp, MoveMsgTag) ->
    case get_slide_op(State, MoveFullId) of
        {ok, PredOrSucc, SlideOp} ->
            case PredOrSuccExp =:= both orelse PredOrSucc =:= PredOrSuccExp of
                true ->
                    case lists:member(slide_op:get_phase(SlideOp), WorkPhases) of
                        true -> WorkerFun(SlideOp, PredOrSucc, State);
                        _    -> State
                    end;
                _ ->
                    % abort slide but do not notify the other node
                    % (this message should not have been received anyway!)
                    ErrorMsg = io_lib:format("~.0p received for a slide with ~s, but only expected for slides with~s~n",
                                             [MoveMsgTag, PredOrSucc, PredOrSuccExp]),
                    NewState = abort_slide(State, SlideOp, {protocol_error, ErrorMsg}, false),
                    log:log(warn, "[ dht_node_move ~.0p ] ~.0p received for a slide with my ~s, but only expected for slides with ~s~n"
                                      "(operation: ~.0p)~n", [comm:this(), MoveMsgTag, PredOrSucc, PredOrSuccExp, SlideOp]),
                    NewState
            end;
        not_found when MoveMsgTag =:= rm_new_pred ->
            % ignore (local) rm_new_pred messages arriving too late
            case util:is_my_old_uid(MoveFullId) of
                true -> ok;
                remote ->
                    log:log(info,"[ dht_node_move ~.0p ] ~.0p received with no "
                           "matching slide operation (ID: ~.0p, slide_pred: ~.0p, slide_succ: ~.0p)~n",
                            [comm:this(), MoveMsgTag, MoveFullId,
                             dht_node_state:get(State, slide_pred),
                             dht_node_state:get(State, slide_succ)]);
                _ ->
                    log:log(warn,"[ dht_node_move ~.0p ] ~.0p received with no "
                           "matching slide operation (ID: ~.0p, slide_pred: ~.0p, slide_succ: ~.0p)~n",
                            [comm:this(), MoveMsgTag, MoveFullId,
                             dht_node_state:get(State, slide_pred),
                             dht_node_state:get(State, slide_succ)])
            end,
            State;
        not_found ->
            log:log(warn,"[ dht_node_move ~.0p ] ~.0p received with no matching "
                   "slide operation (ID: ~.0p, slide_pred: ~.0p, slide_succ: ~.0p)~n",
                    [comm:this(), MoveMsgTag, MoveFullId,
                     dht_node_state:get(State, slide_pred),
                     dht_node_state:get(State, slide_succ)]),
            State;
        {wrong_neighbor, PredOrSucc, SlideOp} -> % wrong pred or succ
            case lists:member(slide_op:get_phase(SlideOp), WorkPhases) of
                true ->
                    NewState = abort_slide(State, SlideOp, wrong_pred_succ_node, true),
                    log:log(warn,"[ dht_node_move ~.0p ] ~.0p received but ~s "
                           "changed during move (ID: ~.0p, node(slide): ~.0p, new_~s: ~.0p)~n",
                            [comm:this(), MoveMsgTag, PredOrSucc, MoveFullId,
                             slide_op:get_node(SlideOp),
                             PredOrSucc, dht_node_state:get(State, PredOrSucc)]),
                    NewState;
                _ -> State
            end
    end.

%% @doc Tries to find a slide operation with the given MoveFullId and returns
%%      it including its type (pred or succ) if successful and its pred/succ
%%      info is correct (a wrong predecessor is tolerated if the slide
%%      operation is a leave since the node will leave and thus we will get
%%      a new predecessor). Otherwise returns {fail, wrong_pred} if the
%%      predecessor info is wrong (slide with pred) and {fail, wrong_succ} if
%%      the successor info is wrong (slide with succ). If not found,
%%      {fail, not_found} is returned.
-spec get_slide_op(State::dht_node_state:state(), MoveFullId::slide_op:id()) ->
        {Result::ok, Type::pred | succ, SlideOp::slide_op:slide_op()} |
        {Result::wrong_neighbor, Type::pred | succ, SlideOp::slide_op:slide_op()} |
        not_found.
get_slide_op(State, MoveFullId) ->
    case dht_node_state:get_slide_op(State, MoveFullId) of
        not_found -> not_found;
        {PredOrSucc, SlideOp} ->
            Node = dht_node_state:get(State, PredOrSucc),
            case node:same_process(Node, slide_op:get_node(SlideOp)) orelse
                     (slide_op:is_leave(SlideOp) andalso PredOrSucc =:= pred) of
                true -> {ok,             PredOrSucc, SlideOp};
                _    -> {wrong_neighbor, PredOrSucc, SlideOp}
            end
    end.

%% @doc Returns whether a slide with the successor is possible for the given
%%      target id.
%% @see can_slide/3
-spec can_slide_succ(State::dht_node_state:state(), TargetId::?RT:key(), Type::slide_op:type()) -> boolean().
can_slide_succ(State, TargetId, Type) ->
    SlidePred = dht_node_state:get(State, slide_pred),
    dht_node_state:get(State, slide_succ) =:= null andalso
        (SlidePred =:= null orelse
             (not intervals:in(TargetId, slide_op:get_interval(SlidePred)) andalso
                  not (slide_op:is_leave(Type) andalso slide_op:is_leave(SlidePred)))
        ).

%% @doc Returns whether a slide with the predecessor is possible for the given
%%      target id.
%% @see can_slide/3
-spec can_slide_pred(State::dht_node_state:state(), TargetId::?RT:key(), Type::slide_op:type()) -> boolean().
can_slide_pred(State, TargetId, _Type) ->
    SlideSucc = dht_node_state:get(State, slide_succ),
    dht_node_state:get(State, slide_pred) =:= null andalso
        (SlideSucc =:= null orelse
             (not intervals:in(TargetId, slide_op:get_interval(SlideSucc)) andalso
                  not slide_op:is_leave(SlideSucc))
        ).

%% @doc Sends the source pid the given message if it is not 'null'.
-spec notify_source_pid(SourcePid::comm:erl_local_pid() | null, Message::result_message()) -> ok.
notify_source_pid(SourcePid, Message) ->
    case SourcePid of
        null -> ok;
        _ -> ?TRACE_SEND(SourcePid, Message),
             comm:send_local(SourcePid, Message)
    end.

%% @doc Aborts the given slide operation. Assume the SlideOp has already been
%%      set in the dht_node and resets the according slide in its state to
%%      null.
%% @see abort_slide/8
-spec abort_slide(State::dht_node_state:state(), SlideOp::slide_op:slide_op(),
        Reason::abort_reason(), NotifyNode::boolean()) -> dht_node_state:state().
abort_slide(State, SlideOp, Reason, NotifyNode) ->
    % write to log when aborting an already set-up slide:
    log:log(warn, "[ dht_node_move ~.0p ] abort_slide(op: ~.0p, reason: ~.0p)~n",
            [comm:this(), SlideOp, Reason]),
    SlideOp1 = slide_op:reset_timer(SlideOp), % reset previous timeouts
    % potentially set up for joining nodes (slide with pred) or
    % nodes sending data to their predecessor:
    RMSubscrTag = {move, slide_op:get_id(SlideOp1)},
    rm_loop:unsubscribe(self(), RMSubscrTag),
    State1 = dht_node_state:rm_db_range(State, slide_op:get_interval(SlideOp1)),
    State2 = dht_node_state:rm_msg_fwd(State1, slide_op:get_interval(SlideOp1)),
    % set a 'null' slide_op if there was an old one with the given ID
    Type = slide_op:get_type(SlideOp1),
    PredOrSucc = slide_op:get_predORsucc(Type),
    State3 = dht_node_state:set_slide(State2, PredOrSucc, null),
    NewDB = ?DB:stop_record_changes(dht_node_state:get(State3, db),
                                    slide_op:get_interval(SlideOp)),
    State4 = dht_node_state:set_db(State3, NewDB),
    abort_slide(State4, slide_op:get_node(SlideOp1), slide_op:get_id(SlideOp1),
                slide_op:get_phase(SlideOp1),
                slide_op:get_source_pid(SlideOp1), slide_op:get_tag(SlideOp1),
                Type, Reason, NotifyNode).

%% @doc Like abort_slide/5 but does not need a slide operation in order to
%%      work. Note: prefer using abort_slide/5 when a slide operation is
%%      available as this also resets all its timers!
-spec abort_slide(State::dht_node_state:state(), Node::node:node_type(),
                  SlideOpId::slide_op:id(), Phase::slide_op:phase(),
                  SourcePid::comm:erl_local_pid() | null,
                  Tag::any(), Type::slide_op:type(), Reason::abort_reason(),
                  NotifyNode::boolean()) -> dht_node_state:state().
abort_slide(State, Node, SlideOpId, _Phase, SourcePid, Tag, Type, Reason, NotifyNode) ->
    PredOrSucc = slide_op:get_predORsucc(Type),
    % abort slide on the (other) node:
    case NotifyNode of
        true ->
            PredOrSuccOther = case PredOrSucc of
                                  pred -> succ;
                                  succ -> pred
                              end,
            Msg = {move, slide_abort, PredOrSuccOther, SlideOpId, Reason},
            ?TRACE_SEND(node:pidX(Node), Msg),
            comm:send(node:pidX(Node), Msg);
        _ -> ok
    end,
    notify_source_pid(SourcePid, {move, result, Tag, Reason}),
    % re-start a leaving slide on the leaving node if it hasn't left the ring yet:
    case slide_op:is_leave(Type, 'send') andalso
             not slide_op:is_jump(Type) of
        true -> make_slide_leave(State);
        _    -> State
    end.

%% @doc Creates a slide with the node's successor or predecessor. TargetId will
%%      become the ID between the two nodes, i.e. either the current node or
%%      the other node will change its ID to TargetId. SourcePid will be
%%      notified about the result.
-spec make_slide(State::dht_node_state:state(), pred | succ, TargetId::?RT:key(),
        Tag::any(), SourcePid::comm:erl_local_pid() | null) -> dht_node_state:state().
make_slide(State, PredOrSucc, TargetId, Tag, SourcePid) ->
    % slide with PredOrSucc possible? if so, receive or send data?
    SendOrReceive =
        case PredOrSucc of
            succ ->
                case intervals:in(TargetId, dht_node_state:get(State, succ_range)) of
                    true -> 'rcv';
                    _    -> 'send'
                end;
            pred ->
                case dht_node_state:is_responsible(TargetId, State) of
                    true -> 'send';
                    _    -> 'rcv'
                end
        end,
    MoveFullId = util:get_global_uid(),
    MyNode = dht_node_state:get(State, node),
    TargetNode = dht_node_state:get(State, PredOrSucc),
    setup_slide(State, {slide, PredOrSucc, SendOrReceive},
                MoveFullId, MyNode, TargetNode, TargetId, Tag,
                unknown, SourcePid, nomsg, {none}).

%% @doc Creates a slide with the node's predecessor. The predecessor will
%%      change its ID to TargetId, SourcePid will be notified about the result.
-spec make_jump(State::dht_node_state:state(), TargetId::?RT:key(),
                Tag::any(), SourcePid::comm:erl_local_pid() | null)
    -> dht_node_state:state().
make_jump(State, TargetId, Tag, SourcePid) ->
    MoveFullId = util:get_global_uid(),
    MyNode = dht_node_state:get(State, node),
    TargetNode = dht_node_state:get(State, succ),
    log:log(info, "[ Node ~.0p ] starting jump (succ: ~.0p, TargetId: ~.0p)~n",
            [MyNode, TargetNode, TargetId]),
    setup_slide(State, {jump, 'send'},
                MoveFullId, MyNode, TargetNode, TargetId, Tag,
                unknown, SourcePid, nomsg, {none}).

%% @doc Creates a slide that will move all data to the successor and leave the
%%      ring. Note: Will re-try (forever) to successfully start a leaving slide
%%      if anything causes an abort!
-spec make_slide_leave(State::dht_node_state:state()) -> dht_node_state:state().
make_slide_leave(State) ->
    MoveFullId = util:get_global_uid(),
    InitNode = dht_node_state:get(State, node),
    OtherNode = dht_node_state:get(State, succ),
    log:log(info, "[ Node ~.0p ] starting leave (succ: ~.0p)~n", [InitNode, OtherNode]),
    setup_slide(State, {leave, 'send'}, MoveFullId, InitNode,
                OtherNode, node:id(OtherNode), leave,
                unknown, null, nomsg, {none}).

%% @doc Send a  node change update message to this module inside the dht_node.
%%      Will be registered with the dht_node as a node change subscriber.
%% @see dht_node_state:add_nc_subscr/3
-spec rm_send_node_change(Pid::pid(), Tag::{move, slide_op:type(), slide_op:id()},
                       OldNeighbors::nodelist:neighborhood(),
                       NewNeighbors::nodelist:neighborhood()) -> ok.
rm_send_node_change(Pid, Tag, _OldNeighbors, _NewNeighbors) ->
    ?TRACE_SEND(Pid, {move, node_update, Tag}),
    comm:send_local(Pid, {move, node_update, Tag}).

%% @doc Sends a rm_new_pred message to the dht_node_move module when a new
%%      predecessor appears at the rm-process. Used in the rm-subscription
%%      during a node join - see dht_node_join.erl.
-spec rm_notify_new_pred(Pid::pid(), Tag::{move, slide_op:type(), slide_op:id()},
        OldNeighbors::nodelist:neighborhood(), NewNeighbors::nodelist:neighborhood()) -> ok.
rm_notify_new_pred(Pid, Tag, _OldNeighbors, _NewNeighbors) ->
    ?TRACE_SEND(Pid, {move, rm_new_pred, Tag}),
    comm:send_local(Pid, {move, rm_new_pred, Tag}).

%% @doc Subscribes the node to a change of the predecessor and calls
%%      dht_node_move:rm_notify_new_pred/4 when the predecessor changes or
%%      the predecessor gets the target ID of the slide operation.
-spec rm_subscribe_to_pred_change(SlideOp::slide_op:slide_op()) -> ok.
rm_subscribe_to_pred_change(SlideOp) ->
    ExpPredId = slide_op:get_target_id(SlideOp),
    RMSubscrTag = {move, slide_op:get_id(SlideOp)},
    rm_loop:subscribe(
      self(), RMSubscrTag,
      fun(OldNeighbors, NewNeighbors) ->
              nodelist:pred(OldNeighbors) =/= nodelist:pred(NewNeighbors) orelse
                  node:id(nodelist:pred(NewNeighbors)) =:= ExpPredId
      end,
      fun dht_node_move:rm_notify_new_pred/4, 1).

%% @doc Checks whether config parameters regarding dht_node moves exist and are
%%      valid.
-spec check_config() -> boolean().
check_config() ->
    config:is_integer(move_max_transport_entries) and
    config:is_greater_than(move_max_transport_entries, 0) and

    config:is_integer(move_notify_other_timeout) and
    config:is_greater_than(move_notify_other_timeout, 0) and

    config:is_integer(move_notify_other_retries) and
    config:is_greater_than(move_notify_other_retries, 0) and

    config:is_integer(move_send_data_timeout) and
    config:is_greater_than(move_send_data_timeout, 0) and

    config:is_integer(move_send_data_retries) and
    config:is_greater_than(move_send_data_retries, 0) and

    config:is_integer(move_send_delta_timeout) and
    config:is_greater_than(move_send_delta_timeout, 0) and

    config:is_integer(move_send_delta_retries) and
    config:is_greater_than(move_send_delta_retries, 0) and

    config:is_integer(move_rcv_data_timeout) and
    config:is_greater_than(move_rcv_data_timeout, 0) and

    config:is_integer(move_rcv_data_retries) and
    config:is_greater_than(move_rcv_data_retries, 0) and

    config:is_integer(move_rcv_delta_timeout) and
    config:is_greater_than(move_rcv_delta_timeout, 0) and

    config:is_integer(move_rcv_delta_retries) and
    config:is_greater_than(move_rcv_delta_retries, 0) and

    config:is_bool(move_use_incremental_slides) and
    config:is_bool(move_symmetric_incremental_slides).
    
%% @doc Gets the max number of DB entries per data move operation (set in the
%%      config files).
-spec get_max_transport_entries() -> pos_integer().
get_max_transport_entries() ->
    config:read(move_max_transport_entries).

%% @doc Gets the max number of ms to wait for the other node's reply when
%%      initiating a move (set in the config files).
-spec get_notify_other_timeout() -> pos_integer().
get_notify_other_timeout() ->
    config:read(move_notify_other_timeout).

%% @doc Gets the max number of retries to notify the other node when
%%      initiating a move (set in the config files).
-spec get_notify_other_retries() -> pos_integer().
get_notify_other_retries() ->
    config:read(move_notify_other_retries).

%% @doc Gets the max number of ms to wait for the succ/pred's reply after
%%      sending data to it (set in the config files).
-spec get_send_data_timeout() -> pos_integer().
get_send_data_timeout() ->
    config:read(move_send_data_timeout).

%% @doc Gets the max number of retries to send data to the succ/pred
%%      (set in the config files).
-spec get_send_data_retries() -> pos_integer().
get_send_data_retries() ->
    config:read(move_send_data_retries).

%% @doc Gets the max number of ms to wait for the succ/pred's reply after
%%      sending delta data to it (set in the config files).
-spec get_send_delta_timeout() -> pos_integer().
get_send_delta_timeout() ->
    config:read(move_send_delta_timeout).

%% @doc Gets the max number of retries to send delta to the succ/pred
%%      (set in the config files).
-spec get_send_delta_retries() -> pos_integer().
get_send_delta_retries() ->
    config:read(move_send_delta_retries).

%% @doc Gets the max number of ms to wait for the succ/pred's reply after
%%      requesting data from it (set in the config files).
-spec get_rcv_data_timeout() -> pos_integer().
get_rcv_data_timeout() ->
    config:read(move_rcv_data_timeout).

%% @doc Gets the max number of retries to send a data request to the succ/pred
%%      (set in the config files).
-spec get_rcv_data_retries() -> pos_integer().
get_rcv_data_retries() ->
    config:read(move_rcv_data_retries).

%% @doc Gets the max number of ms to wait for the succ/pred's reply after
%%      sending data_ack to it (set in the config files).
-spec get_rcv_delta_timeout() -> pos_integer().
get_rcv_delta_timeout() ->
    config:read(move_rcv_delta_timeout).

%% @doc Gets the max number of retries to send a data_ack to the succ/pred
%%      (set in the config files).
-spec get_rcv_delta_retries() -> pos_integer().
get_rcv_delta_retries() ->
    config:read(move_rcv_delta_retries).

%% @doc Checks whether incremental slides are to be used
%%      (set in the config files).
-spec use_incremental_slides() -> boolean().
use_incremental_slides() ->
    config:read(move_use_incremental_slides).

%% @doc Checks whether symmetric incremental slides are to be used (only if
%%      move_use_incremental_slides is activated) (set in the config files).
-spec use_symmetric_incremental_slides() -> boolean().
use_symmetric_incremental_slides() ->
    config:read(move_use_incremental_slides) andalso
        config:read(move_symmetric_incremental_slides).
