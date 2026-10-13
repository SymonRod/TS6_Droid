// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'api.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$TsEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TsEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'TsEvent()';
}


}

/// @nodoc
class $TsEventCopyWith<$Res>  {
$TsEventCopyWith(TsEvent _, $Res Function(TsEvent) __);
}


/// Adds pattern-matching-related methods to [TsEvent].
extension TsEventPatterns on TsEvent {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( TsEvent_ConnectionStateChanged value)?  connectionStateChanged,TResult Function( TsEvent_Connected value)?  connected,TResult Function( TsEvent_Disconnected value)?  disconnected,TResult Function( TsEvent_ConnectionLost value)?  connectionLost,TResult Function( TsEvent_ChannelCreated value)?  channelCreated,TResult Function( TsEvent_ChannelDeleted value)?  channelDeleted,TResult Function( TsEvent_ChannelEdited value)?  channelEdited,TResult Function( TsEvent_ChannelJoined value)?  channelJoined,TResult Function( TsEvent_UserJoined value)?  userJoined,TResult Function( TsEvent_UserLeft value)?  userLeft,TResult Function( TsEvent_UserMoved value)?  userMoved,TResult Function( TsEvent_UserKickedFromChannel value)?  userKickedFromChannel,TResult Function( TsEvent_UserKickedFromServer value)?  userKickedFromServer,TResult Function( TsEvent_UserBanned value)?  userBanned,TResult Function( TsEvent_UserUpdated value)?  userUpdated,TResult Function( TsEvent_TalkStatusStart value)?  talkStatusStart,TResult Function( TsEvent_TalkStatusStop value)?  talkStatusStop,TResult Function( TsEvent_TextMessage value)?  textMessage,TResult Function( TsEvent_Poked value)?  poked,TResult Function( TsEvent_CommandError value)?  commandError,TResult Function( TsEvent_ChannelPermissionsUpdated value)?  channelPermissionsUpdated,TResult Function( TsEvent_StreamsChanged value)?  streamsChanged,TResult Function( TsEvent_StreamJoinResponse value)?  streamJoinResponse,TResult Function( TsEvent_StreamSignaling value)?  streamSignaling,required TResult orElse(),}){
final _that = this;
switch (_that) {
case TsEvent_ConnectionStateChanged() when connectionStateChanged != null:
return connectionStateChanged(_that);case TsEvent_Connected() when connected != null:
return connected(_that);case TsEvent_Disconnected() when disconnected != null:
return disconnected(_that);case TsEvent_ConnectionLost() when connectionLost != null:
return connectionLost(_that);case TsEvent_ChannelCreated() when channelCreated != null:
return channelCreated(_that);case TsEvent_ChannelDeleted() when channelDeleted != null:
return channelDeleted(_that);case TsEvent_ChannelEdited() when channelEdited != null:
return channelEdited(_that);case TsEvent_ChannelJoined() when channelJoined != null:
return channelJoined(_that);case TsEvent_UserJoined() when userJoined != null:
return userJoined(_that);case TsEvent_UserLeft() when userLeft != null:
return userLeft(_that);case TsEvent_UserMoved() when userMoved != null:
return userMoved(_that);case TsEvent_UserKickedFromChannel() when userKickedFromChannel != null:
return userKickedFromChannel(_that);case TsEvent_UserKickedFromServer() when userKickedFromServer != null:
return userKickedFromServer(_that);case TsEvent_UserBanned() when userBanned != null:
return userBanned(_that);case TsEvent_UserUpdated() when userUpdated != null:
return userUpdated(_that);case TsEvent_TalkStatusStart() when talkStatusStart != null:
return talkStatusStart(_that);case TsEvent_TalkStatusStop() when talkStatusStop != null:
return talkStatusStop(_that);case TsEvent_TextMessage() when textMessage != null:
return textMessage(_that);case TsEvent_Poked() when poked != null:
return poked(_that);case TsEvent_CommandError() when commandError != null:
return commandError(_that);case TsEvent_ChannelPermissionsUpdated() when channelPermissionsUpdated != null:
return channelPermissionsUpdated(_that);case TsEvent_StreamsChanged() when streamsChanged != null:
return streamsChanged(_that);case TsEvent_StreamJoinResponse() when streamJoinResponse != null:
return streamJoinResponse(_that);case TsEvent_StreamSignaling() when streamSignaling != null:
return streamSignaling(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( TsEvent_ConnectionStateChanged value)  connectionStateChanged,required TResult Function( TsEvent_Connected value)  connected,required TResult Function( TsEvent_Disconnected value)  disconnected,required TResult Function( TsEvent_ConnectionLost value)  connectionLost,required TResult Function( TsEvent_ChannelCreated value)  channelCreated,required TResult Function( TsEvent_ChannelDeleted value)  channelDeleted,required TResult Function( TsEvent_ChannelEdited value)  channelEdited,required TResult Function( TsEvent_ChannelJoined value)  channelJoined,required TResult Function( TsEvent_UserJoined value)  userJoined,required TResult Function( TsEvent_UserLeft value)  userLeft,required TResult Function( TsEvent_UserMoved value)  userMoved,required TResult Function( TsEvent_UserKickedFromChannel value)  userKickedFromChannel,required TResult Function( TsEvent_UserKickedFromServer value)  userKickedFromServer,required TResult Function( TsEvent_UserBanned value)  userBanned,required TResult Function( TsEvent_UserUpdated value)  userUpdated,required TResult Function( TsEvent_TalkStatusStart value)  talkStatusStart,required TResult Function( TsEvent_TalkStatusStop value)  talkStatusStop,required TResult Function( TsEvent_TextMessage value)  textMessage,required TResult Function( TsEvent_Poked value)  poked,required TResult Function( TsEvent_CommandError value)  commandError,required TResult Function( TsEvent_ChannelPermissionsUpdated value)  channelPermissionsUpdated,required TResult Function( TsEvent_StreamsChanged value)  streamsChanged,required TResult Function( TsEvent_StreamJoinResponse value)  streamJoinResponse,required TResult Function( TsEvent_StreamSignaling value)  streamSignaling,}){
final _that = this;
switch (_that) {
case TsEvent_ConnectionStateChanged():
return connectionStateChanged(_that);case TsEvent_Connected():
return connected(_that);case TsEvent_Disconnected():
return disconnected(_that);case TsEvent_ConnectionLost():
return connectionLost(_that);case TsEvent_ChannelCreated():
return channelCreated(_that);case TsEvent_ChannelDeleted():
return channelDeleted(_that);case TsEvent_ChannelEdited():
return channelEdited(_that);case TsEvent_ChannelJoined():
return channelJoined(_that);case TsEvent_UserJoined():
return userJoined(_that);case TsEvent_UserLeft():
return userLeft(_that);case TsEvent_UserMoved():
return userMoved(_that);case TsEvent_UserKickedFromChannel():
return userKickedFromChannel(_that);case TsEvent_UserKickedFromServer():
return userKickedFromServer(_that);case TsEvent_UserBanned():
return userBanned(_that);case TsEvent_UserUpdated():
return userUpdated(_that);case TsEvent_TalkStatusStart():
return talkStatusStart(_that);case TsEvent_TalkStatusStop():
return talkStatusStop(_that);case TsEvent_TextMessage():
return textMessage(_that);case TsEvent_Poked():
return poked(_that);case TsEvent_CommandError():
return commandError(_that);case TsEvent_ChannelPermissionsUpdated():
return channelPermissionsUpdated(_that);case TsEvent_StreamsChanged():
return streamsChanged(_that);case TsEvent_StreamJoinResponse():
return streamJoinResponse(_that);case TsEvent_StreamSignaling():
return streamSignaling(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( TsEvent_ConnectionStateChanged value)?  connectionStateChanged,TResult? Function( TsEvent_Connected value)?  connected,TResult? Function( TsEvent_Disconnected value)?  disconnected,TResult? Function( TsEvent_ConnectionLost value)?  connectionLost,TResult? Function( TsEvent_ChannelCreated value)?  channelCreated,TResult? Function( TsEvent_ChannelDeleted value)?  channelDeleted,TResult? Function( TsEvent_ChannelEdited value)?  channelEdited,TResult? Function( TsEvent_ChannelJoined value)?  channelJoined,TResult? Function( TsEvent_UserJoined value)?  userJoined,TResult? Function( TsEvent_UserLeft value)?  userLeft,TResult? Function( TsEvent_UserMoved value)?  userMoved,TResult? Function( TsEvent_UserKickedFromChannel value)?  userKickedFromChannel,TResult? Function( TsEvent_UserKickedFromServer value)?  userKickedFromServer,TResult? Function( TsEvent_UserBanned value)?  userBanned,TResult? Function( TsEvent_UserUpdated value)?  userUpdated,TResult? Function( TsEvent_TalkStatusStart value)?  talkStatusStart,TResult? Function( TsEvent_TalkStatusStop value)?  talkStatusStop,TResult? Function( TsEvent_TextMessage value)?  textMessage,TResult? Function( TsEvent_Poked value)?  poked,TResult? Function( TsEvent_CommandError value)?  commandError,TResult? Function( TsEvent_ChannelPermissionsUpdated value)?  channelPermissionsUpdated,TResult? Function( TsEvent_StreamsChanged value)?  streamsChanged,TResult? Function( TsEvent_StreamJoinResponse value)?  streamJoinResponse,TResult? Function( TsEvent_StreamSignaling value)?  streamSignaling,}){
final _that = this;
switch (_that) {
case TsEvent_ConnectionStateChanged() when connectionStateChanged != null:
return connectionStateChanged(_that);case TsEvent_Connected() when connected != null:
return connected(_that);case TsEvent_Disconnected() when disconnected != null:
return disconnected(_that);case TsEvent_ConnectionLost() when connectionLost != null:
return connectionLost(_that);case TsEvent_ChannelCreated() when channelCreated != null:
return channelCreated(_that);case TsEvent_ChannelDeleted() when channelDeleted != null:
return channelDeleted(_that);case TsEvent_ChannelEdited() when channelEdited != null:
return channelEdited(_that);case TsEvent_ChannelJoined() when channelJoined != null:
return channelJoined(_that);case TsEvent_UserJoined() when userJoined != null:
return userJoined(_that);case TsEvent_UserLeft() when userLeft != null:
return userLeft(_that);case TsEvent_UserMoved() when userMoved != null:
return userMoved(_that);case TsEvent_UserKickedFromChannel() when userKickedFromChannel != null:
return userKickedFromChannel(_that);case TsEvent_UserKickedFromServer() when userKickedFromServer != null:
return userKickedFromServer(_that);case TsEvent_UserBanned() when userBanned != null:
return userBanned(_that);case TsEvent_UserUpdated() when userUpdated != null:
return userUpdated(_that);case TsEvent_TalkStatusStart() when talkStatusStart != null:
return talkStatusStart(_that);case TsEvent_TalkStatusStop() when talkStatusStop != null:
return talkStatusStop(_that);case TsEvent_TextMessage() when textMessage != null:
return textMessage(_that);case TsEvent_Poked() when poked != null:
return poked(_that);case TsEvent_CommandError() when commandError != null:
return commandError(_that);case TsEvent_ChannelPermissionsUpdated() when channelPermissionsUpdated != null:
return channelPermissionsUpdated(_that);case TsEvent_StreamsChanged() when streamsChanged != null:
return streamsChanged(_that);case TsEvent_StreamJoinResponse() when streamJoinResponse != null:
return streamJoinResponse(_that);case TsEvent_StreamSignaling() when streamSignaling != null:
return streamSignaling(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( TsConnectionState newState)?  connectionStateChanged,TResult Function( String serverName,  String? welcomeMessage)?  connected,TResult Function( String reason)?  disconnected,TResult Function( String reason)?  connectionLost,TResult Function( PlatformInt64 channelId,  String name)?  channelCreated,TResult Function( PlatformInt64 channelId)?  channelDeleted,TResult Function( PlatformInt64 channelId,  String name)?  channelEdited,TResult Function( PlatformInt64 channelId,  String name)?  channelJoined,TResult Function( int userId,  String nickname,  PlatformInt64 channelId)?  userJoined,TResult Function( int userId,  String nickname,  String reason)?  userLeft,TResult Function( int userId,  String nickname,  PlatformInt64 fromChannel,  PlatformInt64 toChannel)?  userMoved,TResult Function( int userId,  int kickerId,  String reason)?  userKickedFromChannel,TResult Function( int userId,  int kickerId,  String reason)?  userKickedFromServer,TResult Function( int userId,  int bannerId,  String reason)?  userBanned,TResult Function( int userId,  String nickname)?  userUpdated,TResult Function( int userId)?  talkStatusStart,TResult Function( int userId)?  talkStatusStop,TResult Function( int senderId,  String senderName,  String message,  TsMessageTarget target)?  textMessage,TResult Function( int pokerId,  String pokerName,  String message)?  poked,TResult Function( int errorId,  String message)?  commandError,TResult Function( PlatformInt64 channelId,  PlatformInt64 permissionHints)?  channelPermissionsUpdated,TResult Function( List<TsStream> streams)?  streamsChanged,TResult Function( int ownerId,  String streamId,  bool accepted,  String? message,  String? offer)?  streamJoinResponse,TResult Function( int ownerId,  String streamId,  String json)?  streamSignaling,required TResult orElse(),}) {final _that = this;
switch (_that) {
case TsEvent_ConnectionStateChanged() when connectionStateChanged != null:
return connectionStateChanged(_that.newState);case TsEvent_Connected() when connected != null:
return connected(_that.serverName,_that.welcomeMessage);case TsEvent_Disconnected() when disconnected != null:
return disconnected(_that.reason);case TsEvent_ConnectionLost() when connectionLost != null:
return connectionLost(_that.reason);case TsEvent_ChannelCreated() when channelCreated != null:
return channelCreated(_that.channelId,_that.name);case TsEvent_ChannelDeleted() when channelDeleted != null:
return channelDeleted(_that.channelId);case TsEvent_ChannelEdited() when channelEdited != null:
return channelEdited(_that.channelId,_that.name);case TsEvent_ChannelJoined() when channelJoined != null:
return channelJoined(_that.channelId,_that.name);case TsEvent_UserJoined() when userJoined != null:
return userJoined(_that.userId,_that.nickname,_that.channelId);case TsEvent_UserLeft() when userLeft != null:
return userLeft(_that.userId,_that.nickname,_that.reason);case TsEvent_UserMoved() when userMoved != null:
return userMoved(_that.userId,_that.nickname,_that.fromChannel,_that.toChannel);case TsEvent_UserKickedFromChannel() when userKickedFromChannel != null:
return userKickedFromChannel(_that.userId,_that.kickerId,_that.reason);case TsEvent_UserKickedFromServer() when userKickedFromServer != null:
return userKickedFromServer(_that.userId,_that.kickerId,_that.reason);case TsEvent_UserBanned() when userBanned != null:
return userBanned(_that.userId,_that.bannerId,_that.reason);case TsEvent_UserUpdated() when userUpdated != null:
return userUpdated(_that.userId,_that.nickname);case TsEvent_TalkStatusStart() when talkStatusStart != null:
return talkStatusStart(_that.userId);case TsEvent_TalkStatusStop() when talkStatusStop != null:
return talkStatusStop(_that.userId);case TsEvent_TextMessage() when textMessage != null:
return textMessage(_that.senderId,_that.senderName,_that.message,_that.target);case TsEvent_Poked() when poked != null:
return poked(_that.pokerId,_that.pokerName,_that.message);case TsEvent_CommandError() when commandError != null:
return commandError(_that.errorId,_that.message);case TsEvent_ChannelPermissionsUpdated() when channelPermissionsUpdated != null:
return channelPermissionsUpdated(_that.channelId,_that.permissionHints);case TsEvent_StreamsChanged() when streamsChanged != null:
return streamsChanged(_that.streams);case TsEvent_StreamJoinResponse() when streamJoinResponse != null:
return streamJoinResponse(_that.ownerId,_that.streamId,_that.accepted,_that.message,_that.offer);case TsEvent_StreamSignaling() when streamSignaling != null:
return streamSignaling(_that.ownerId,_that.streamId,_that.json);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( TsConnectionState newState)  connectionStateChanged,required TResult Function( String serverName,  String? welcomeMessage)  connected,required TResult Function( String reason)  disconnected,required TResult Function( String reason)  connectionLost,required TResult Function( PlatformInt64 channelId,  String name)  channelCreated,required TResult Function( PlatformInt64 channelId)  channelDeleted,required TResult Function( PlatformInt64 channelId,  String name)  channelEdited,required TResult Function( PlatformInt64 channelId,  String name)  channelJoined,required TResult Function( int userId,  String nickname,  PlatformInt64 channelId)  userJoined,required TResult Function( int userId,  String nickname,  String reason)  userLeft,required TResult Function( int userId,  String nickname,  PlatformInt64 fromChannel,  PlatformInt64 toChannel)  userMoved,required TResult Function( int userId,  int kickerId,  String reason)  userKickedFromChannel,required TResult Function( int userId,  int kickerId,  String reason)  userKickedFromServer,required TResult Function( int userId,  int bannerId,  String reason)  userBanned,required TResult Function( int userId,  String nickname)  userUpdated,required TResult Function( int userId)  talkStatusStart,required TResult Function( int userId)  talkStatusStop,required TResult Function( int senderId,  String senderName,  String message,  TsMessageTarget target)  textMessage,required TResult Function( int pokerId,  String pokerName,  String message)  poked,required TResult Function( int errorId,  String message)  commandError,required TResult Function( PlatformInt64 channelId,  PlatformInt64 permissionHints)  channelPermissionsUpdated,required TResult Function( List<TsStream> streams)  streamsChanged,required TResult Function( int ownerId,  String streamId,  bool accepted,  String? message,  String? offer)  streamJoinResponse,required TResult Function( int ownerId,  String streamId,  String json)  streamSignaling,}) {final _that = this;
switch (_that) {
case TsEvent_ConnectionStateChanged():
return connectionStateChanged(_that.newState);case TsEvent_Connected():
return connected(_that.serverName,_that.welcomeMessage);case TsEvent_Disconnected():
return disconnected(_that.reason);case TsEvent_ConnectionLost():
return connectionLost(_that.reason);case TsEvent_ChannelCreated():
return channelCreated(_that.channelId,_that.name);case TsEvent_ChannelDeleted():
return channelDeleted(_that.channelId);case TsEvent_ChannelEdited():
return channelEdited(_that.channelId,_that.name);case TsEvent_ChannelJoined():
return channelJoined(_that.channelId,_that.name);case TsEvent_UserJoined():
return userJoined(_that.userId,_that.nickname,_that.channelId);case TsEvent_UserLeft():
return userLeft(_that.userId,_that.nickname,_that.reason);case TsEvent_UserMoved():
return userMoved(_that.userId,_that.nickname,_that.fromChannel,_that.toChannel);case TsEvent_UserKickedFromChannel():
return userKickedFromChannel(_that.userId,_that.kickerId,_that.reason);case TsEvent_UserKickedFromServer():
return userKickedFromServer(_that.userId,_that.kickerId,_that.reason);case TsEvent_UserBanned():
return userBanned(_that.userId,_that.bannerId,_that.reason);case TsEvent_UserUpdated():
return userUpdated(_that.userId,_that.nickname);case TsEvent_TalkStatusStart():
return talkStatusStart(_that.userId);case TsEvent_TalkStatusStop():
return talkStatusStop(_that.userId);case TsEvent_TextMessage():
return textMessage(_that.senderId,_that.senderName,_that.message,_that.target);case TsEvent_Poked():
return poked(_that.pokerId,_that.pokerName,_that.message);case TsEvent_CommandError():
return commandError(_that.errorId,_that.message);case TsEvent_ChannelPermissionsUpdated():
return channelPermissionsUpdated(_that.channelId,_that.permissionHints);case TsEvent_StreamsChanged():
return streamsChanged(_that.streams);case TsEvent_StreamJoinResponse():
return streamJoinResponse(_that.ownerId,_that.streamId,_that.accepted,_that.message,_that.offer);case TsEvent_StreamSignaling():
return streamSignaling(_that.ownerId,_that.streamId,_that.json);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( TsConnectionState newState)?  connectionStateChanged,TResult? Function( String serverName,  String? welcomeMessage)?  connected,TResult? Function( String reason)?  disconnected,TResult? Function( String reason)?  connectionLost,TResult? Function( PlatformInt64 channelId,  String name)?  channelCreated,TResult? Function( PlatformInt64 channelId)?  channelDeleted,TResult? Function( PlatformInt64 channelId,  String name)?  channelEdited,TResult? Function( PlatformInt64 channelId,  String name)?  channelJoined,TResult? Function( int userId,  String nickname,  PlatformInt64 channelId)?  userJoined,TResult? Function( int userId,  String nickname,  String reason)?  userLeft,TResult? Function( int userId,  String nickname,  PlatformInt64 fromChannel,  PlatformInt64 toChannel)?  userMoved,TResult? Function( int userId,  int kickerId,  String reason)?  userKickedFromChannel,TResult? Function( int userId,  int kickerId,  String reason)?  userKickedFromServer,TResult? Function( int userId,  int bannerId,  String reason)?  userBanned,TResult? Function( int userId,  String nickname)?  userUpdated,TResult? Function( int userId)?  talkStatusStart,TResult? Function( int userId)?  talkStatusStop,TResult? Function( int senderId,  String senderName,  String message,  TsMessageTarget target)?  textMessage,TResult? Function( int pokerId,  String pokerName,  String message)?  poked,TResult? Function( int errorId,  String message)?  commandError,TResult? Function( PlatformInt64 channelId,  PlatformInt64 permissionHints)?  channelPermissionsUpdated,TResult? Function( List<TsStream> streams)?  streamsChanged,TResult? Function( int ownerId,  String streamId,  bool accepted,  String? message,  String? offer)?  streamJoinResponse,TResult? Function( int ownerId,  String streamId,  String json)?  streamSignaling,}) {final _that = this;
switch (_that) {
case TsEvent_ConnectionStateChanged() when connectionStateChanged != null:
return connectionStateChanged(_that.newState);case TsEvent_Connected() when connected != null:
return connected(_that.serverName,_that.welcomeMessage);case TsEvent_Disconnected() when disconnected != null:
return disconnected(_that.reason);case TsEvent_ConnectionLost() when connectionLost != null:
return connectionLost(_that.reason);case TsEvent_ChannelCreated() when channelCreated != null:
return channelCreated(_that.channelId,_that.name);case TsEvent_ChannelDeleted() when channelDeleted != null:
return channelDeleted(_that.channelId);case TsEvent_ChannelEdited() when channelEdited != null:
return channelEdited(_that.channelId,_that.name);case TsEvent_ChannelJoined() when channelJoined != null:
return channelJoined(_that.channelId,_that.name);case TsEvent_UserJoined() when userJoined != null:
return userJoined(_that.userId,_that.nickname,_that.channelId);case TsEvent_UserLeft() when userLeft != null:
return userLeft(_that.userId,_that.nickname,_that.reason);case TsEvent_UserMoved() when userMoved != null:
return userMoved(_that.userId,_that.nickname,_that.fromChannel,_that.toChannel);case TsEvent_UserKickedFromChannel() when userKickedFromChannel != null:
return userKickedFromChannel(_that.userId,_that.kickerId,_that.reason);case TsEvent_UserKickedFromServer() when userKickedFromServer != null:
return userKickedFromServer(_that.userId,_that.kickerId,_that.reason);case TsEvent_UserBanned() when userBanned != null:
return userBanned(_that.userId,_that.bannerId,_that.reason);case TsEvent_UserUpdated() when userUpdated != null:
return userUpdated(_that.userId,_that.nickname);case TsEvent_TalkStatusStart() when talkStatusStart != null:
return talkStatusStart(_that.userId);case TsEvent_TalkStatusStop() when talkStatusStop != null:
return talkStatusStop(_that.userId);case TsEvent_TextMessage() when textMessage != null:
return textMessage(_that.senderId,_that.senderName,_that.message,_that.target);case TsEvent_Poked() when poked != null:
return poked(_that.pokerId,_that.pokerName,_that.message);case TsEvent_CommandError() when commandError != null:
return commandError(_that.errorId,_that.message);case TsEvent_ChannelPermissionsUpdated() when channelPermissionsUpdated != null:
return channelPermissionsUpdated(_that.channelId,_that.permissionHints);case TsEvent_StreamsChanged() when streamsChanged != null:
return streamsChanged(_that.streams);case TsEvent_StreamJoinResponse() when streamJoinResponse != null:
return streamJoinResponse(_that.ownerId,_that.streamId,_that.accepted,_that.message,_that.offer);case TsEvent_StreamSignaling() when streamSignaling != null:
return streamSignaling(_that.ownerId,_that.streamId,_that.json);case _:
  return null;

}
}

}

/// @nodoc


class TsEvent_ConnectionStateChanged extends TsEvent {
  const TsEvent_ConnectionStateChanged({required this.newState}): super._();
  

 final  TsConnectionState newState;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TsEvent_ConnectionStateChangedCopyWith<TsEvent_ConnectionStateChanged> get copyWith => _$TsEvent_ConnectionStateChangedCopyWithImpl<TsEvent_ConnectionStateChanged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TsEvent_ConnectionStateChanged&&(identical(other.newState, newState) || other.newState == newState));
}


@override
int get hashCode => Object.hash(runtimeType,newState);

@override
String toString() {
  return 'TsEvent.connectionStateChanged(newState: $newState)';
}


}

/// @nodoc
abstract mixin class $TsEvent_ConnectionStateChangedCopyWith<$Res> implements $TsEventCopyWith<$Res> {
  factory $TsEvent_ConnectionStateChangedCopyWith(TsEvent_ConnectionStateChanged value, $Res Function(TsEvent_ConnectionStateChanged) _then) = _$TsEvent_ConnectionStateChangedCopyWithImpl;
@useResult
$Res call({
 TsConnectionState newState
});




}
/// @nodoc
class _$TsEvent_ConnectionStateChangedCopyWithImpl<$Res>
    implements $TsEvent_ConnectionStateChangedCopyWith<$Res> {
  _$TsEvent_ConnectionStateChangedCopyWithImpl(this._self, this._then);

  final TsEvent_ConnectionStateChanged _self;
  final $Res Function(TsEvent_ConnectionStateChanged) _then;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? newState = null,}) {
  return _then(TsEvent_ConnectionStateChanged(
newState: null == newState ? _self.newState : newState // ignore: cast_nullable_to_non_nullable
as TsConnectionState,
  ));
}


}

/// @nodoc


class TsEvent_Connected extends TsEvent {
  const TsEvent_Connected({required this.serverName, this.welcomeMessage}): super._();
  

 final  String serverName;
 final  String? welcomeMessage;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TsEvent_ConnectedCopyWith<TsEvent_Connected> get copyWith => _$TsEvent_ConnectedCopyWithImpl<TsEvent_Connected>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TsEvent_Connected&&(identical(other.serverName, serverName) || other.serverName == serverName)&&(identical(other.welcomeMessage, welcomeMessage) || other.welcomeMessage == welcomeMessage));
}


@override
int get hashCode => Object.hash(runtimeType,serverName,welcomeMessage);

@override
String toString() {
  return 'TsEvent.connected(serverName: $serverName, welcomeMessage: $welcomeMessage)';
}


}

/// @nodoc
abstract mixin class $TsEvent_ConnectedCopyWith<$Res> implements $TsEventCopyWith<$Res> {
  factory $TsEvent_ConnectedCopyWith(TsEvent_Connected value, $Res Function(TsEvent_Connected) _then) = _$TsEvent_ConnectedCopyWithImpl;
@useResult
$Res call({
 String serverName, String? welcomeMessage
});




}
/// @nodoc
class _$TsEvent_ConnectedCopyWithImpl<$Res>
    implements $TsEvent_ConnectedCopyWith<$Res> {
  _$TsEvent_ConnectedCopyWithImpl(this._self, this._then);

  final TsEvent_Connected _self;
  final $Res Function(TsEvent_Connected) _then;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? serverName = null,Object? welcomeMessage = freezed,}) {
  return _then(TsEvent_Connected(
serverName: null == serverName ? _self.serverName : serverName // ignore: cast_nullable_to_non_nullable
as String,welcomeMessage: freezed == welcomeMessage ? _self.welcomeMessage : welcomeMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class TsEvent_Disconnected extends TsEvent {
  const TsEvent_Disconnected({required this.reason}): super._();
  

 final  String reason;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TsEvent_DisconnectedCopyWith<TsEvent_Disconnected> get copyWith => _$TsEvent_DisconnectedCopyWithImpl<TsEvent_Disconnected>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TsEvent_Disconnected&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,reason);

@override
String toString() {
  return 'TsEvent.disconnected(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $TsEvent_DisconnectedCopyWith<$Res> implements $TsEventCopyWith<$Res> {
  factory $TsEvent_DisconnectedCopyWith(TsEvent_Disconnected value, $Res Function(TsEvent_Disconnected) _then) = _$TsEvent_DisconnectedCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class _$TsEvent_DisconnectedCopyWithImpl<$Res>
    implements $TsEvent_DisconnectedCopyWith<$Res> {
  _$TsEvent_DisconnectedCopyWithImpl(this._self, this._then);

  final TsEvent_Disconnected _self;
  final $Res Function(TsEvent_Disconnected) _then;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(TsEvent_Disconnected(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class TsEvent_ConnectionLost extends TsEvent {
  const TsEvent_ConnectionLost({required this.reason}): super._();
  

 final  String reason;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TsEvent_ConnectionLostCopyWith<TsEvent_ConnectionLost> get copyWith => _$TsEvent_ConnectionLostCopyWithImpl<TsEvent_ConnectionLost>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TsEvent_ConnectionLost&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,reason);

@override
String toString() {
  return 'TsEvent.connectionLost(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $TsEvent_ConnectionLostCopyWith<$Res> implements $TsEventCopyWith<$Res> {
  factory $TsEvent_ConnectionLostCopyWith(TsEvent_ConnectionLost value, $Res Function(TsEvent_ConnectionLost) _then) = _$TsEvent_ConnectionLostCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class _$TsEvent_ConnectionLostCopyWithImpl<$Res>
    implements $TsEvent_ConnectionLostCopyWith<$Res> {
  _$TsEvent_ConnectionLostCopyWithImpl(this._self, this._then);

  final TsEvent_ConnectionLost _self;
  final $Res Function(TsEvent_ConnectionLost) _then;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(TsEvent_ConnectionLost(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class TsEvent_ChannelCreated extends TsEvent {
  const TsEvent_ChannelCreated({required this.channelId, required this.name}): super._();
  

 final  PlatformInt64 channelId;
 final  String name;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TsEvent_ChannelCreatedCopyWith<TsEvent_ChannelCreated> get copyWith => _$TsEvent_ChannelCreatedCopyWithImpl<TsEvent_ChannelCreated>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TsEvent_ChannelCreated&&(identical(other.channelId, channelId) || other.channelId == channelId)&&(identical(other.name, name) || other.name == name));
}


@override
int get hashCode => Object.hash(runtimeType,channelId,name);

@override
String toString() {
  return 'TsEvent.channelCreated(channelId: $channelId, name: $name)';
}


}

/// @nodoc
abstract mixin class $TsEvent_ChannelCreatedCopyWith<$Res> implements $TsEventCopyWith<$Res> {
  factory $TsEvent_ChannelCreatedCopyWith(TsEvent_ChannelCreated value, $Res Function(TsEvent_ChannelCreated) _then) = _$TsEvent_ChannelCreatedCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 channelId, String name
});




}
/// @nodoc
class _$TsEvent_ChannelCreatedCopyWithImpl<$Res>
    implements $TsEvent_ChannelCreatedCopyWith<$Res> {
  _$TsEvent_ChannelCreatedCopyWithImpl(this._self, this._then);

  final TsEvent_ChannelCreated _self;
  final $Res Function(TsEvent_ChannelCreated) _then;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? channelId = null,Object? name = null,}) {
  return _then(TsEvent_ChannelCreated(
channelId: null == channelId ? _self.channelId : channelId // ignore: cast_nullable_to_non_nullable
as PlatformInt64,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class TsEvent_ChannelDeleted extends TsEvent {
  const TsEvent_ChannelDeleted({required this.channelId}): super._();
  

 final  PlatformInt64 channelId;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TsEvent_ChannelDeletedCopyWith<TsEvent_ChannelDeleted> get copyWith => _$TsEvent_ChannelDeletedCopyWithImpl<TsEvent_ChannelDeleted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TsEvent_ChannelDeleted&&(identical(other.channelId, channelId) || other.channelId == channelId));
}


@override
int get hashCode => Object.hash(runtimeType,channelId);

@override
String toString() {
  return 'TsEvent.channelDeleted(channelId: $channelId)';
}


}

/// @nodoc
abstract mixin class $TsEvent_ChannelDeletedCopyWith<$Res> implements $TsEventCopyWith<$Res> {
  factory $TsEvent_ChannelDeletedCopyWith(TsEvent_ChannelDeleted value, $Res Function(TsEvent_ChannelDeleted) _then) = _$TsEvent_ChannelDeletedCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 channelId
});




}
/// @nodoc
class _$TsEvent_ChannelDeletedCopyWithImpl<$Res>
    implements $TsEvent_ChannelDeletedCopyWith<$Res> {
  _$TsEvent_ChannelDeletedCopyWithImpl(this._self, this._then);

  final TsEvent_ChannelDeleted _self;
  final $Res Function(TsEvent_ChannelDeleted) _then;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? channelId = null,}) {
  return _then(TsEvent_ChannelDeleted(
channelId: null == channelId ? _self.channelId : channelId // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class TsEvent_ChannelEdited extends TsEvent {
  const TsEvent_ChannelEdited({required this.channelId, required this.name}): super._();
  

 final  PlatformInt64 channelId;
 final  String name;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TsEvent_ChannelEditedCopyWith<TsEvent_ChannelEdited> get copyWith => _$TsEvent_ChannelEditedCopyWithImpl<TsEvent_ChannelEdited>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TsEvent_ChannelEdited&&(identical(other.channelId, channelId) || other.channelId == channelId)&&(identical(other.name, name) || other.name == name));
}


@override
int get hashCode => Object.hash(runtimeType,channelId,name);

@override
String toString() {
  return 'TsEvent.channelEdited(channelId: $channelId, name: $name)';
}


}

/// @nodoc
abstract mixin class $TsEvent_ChannelEditedCopyWith<$Res> implements $TsEventCopyWith<$Res> {
  factory $TsEvent_ChannelEditedCopyWith(TsEvent_ChannelEdited value, $Res Function(TsEvent_ChannelEdited) _then) = _$TsEvent_ChannelEditedCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 channelId, String name
});




}
/// @nodoc
class _$TsEvent_ChannelEditedCopyWithImpl<$Res>
    implements $TsEvent_ChannelEditedCopyWith<$Res> {
  _$TsEvent_ChannelEditedCopyWithImpl(this._self, this._then);

  final TsEvent_ChannelEdited _self;
  final $Res Function(TsEvent_ChannelEdited) _then;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? channelId = null,Object? name = null,}) {
  return _then(TsEvent_ChannelEdited(
channelId: null == channelId ? _self.channelId : channelId // ignore: cast_nullable_to_non_nullable
as PlatformInt64,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class TsEvent_ChannelJoined extends TsEvent {
  const TsEvent_ChannelJoined({required this.channelId, required this.name}): super._();
  

 final  PlatformInt64 channelId;
 final  String name;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TsEvent_ChannelJoinedCopyWith<TsEvent_ChannelJoined> get copyWith => _$TsEvent_ChannelJoinedCopyWithImpl<TsEvent_ChannelJoined>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TsEvent_ChannelJoined&&(identical(other.channelId, channelId) || other.channelId == channelId)&&(identical(other.name, name) || other.name == name));
}


@override
int get hashCode => Object.hash(runtimeType,channelId,name);

@override
String toString() {
  return 'TsEvent.channelJoined(channelId: $channelId, name: $name)';
}


}

/// @nodoc
abstract mixin class $TsEvent_ChannelJoinedCopyWith<$Res> implements $TsEventCopyWith<$Res> {
  factory $TsEvent_ChannelJoinedCopyWith(TsEvent_ChannelJoined value, $Res Function(TsEvent_ChannelJoined) _then) = _$TsEvent_ChannelJoinedCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 channelId, String name
});




}
/// @nodoc
class _$TsEvent_ChannelJoinedCopyWithImpl<$Res>
    implements $TsEvent_ChannelJoinedCopyWith<$Res> {
  _$TsEvent_ChannelJoinedCopyWithImpl(this._self, this._then);

  final TsEvent_ChannelJoined _self;
  final $Res Function(TsEvent_ChannelJoined) _then;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? channelId = null,Object? name = null,}) {
  return _then(TsEvent_ChannelJoined(
channelId: null == channelId ? _self.channelId : channelId // ignore: cast_nullable_to_non_nullable
as PlatformInt64,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class TsEvent_UserJoined extends TsEvent {
  const TsEvent_UserJoined({required this.userId, required this.nickname, required this.channelId}): super._();
  

 final  int userId;
 final  String nickname;
 final  PlatformInt64 channelId;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TsEvent_UserJoinedCopyWith<TsEvent_UserJoined> get copyWith => _$TsEvent_UserJoinedCopyWithImpl<TsEvent_UserJoined>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TsEvent_UserJoined&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.nickname, nickname) || other.nickname == nickname)&&(identical(other.channelId, channelId) || other.channelId == channelId));
}


@override
int get hashCode => Object.hash(runtimeType,userId,nickname,channelId);

@override
String toString() {
  return 'TsEvent.userJoined(userId: $userId, nickname: $nickname, channelId: $channelId)';
}


}

/// @nodoc
abstract mixin class $TsEvent_UserJoinedCopyWith<$Res> implements $TsEventCopyWith<$Res> {
  factory $TsEvent_UserJoinedCopyWith(TsEvent_UserJoined value, $Res Function(TsEvent_UserJoined) _then) = _$TsEvent_UserJoinedCopyWithImpl;
@useResult
$Res call({
 int userId, String nickname, PlatformInt64 channelId
});




}
/// @nodoc
class _$TsEvent_UserJoinedCopyWithImpl<$Res>
    implements $TsEvent_UserJoinedCopyWith<$Res> {
  _$TsEvent_UserJoinedCopyWithImpl(this._self, this._then);

  final TsEvent_UserJoined _self;
  final $Res Function(TsEvent_UserJoined) _then;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? userId = null,Object? nickname = null,Object? channelId = null,}) {
  return _then(TsEvent_UserJoined(
userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as int,nickname: null == nickname ? _self.nickname : nickname // ignore: cast_nullable_to_non_nullable
as String,channelId: null == channelId ? _self.channelId : channelId // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class TsEvent_UserLeft extends TsEvent {
  const TsEvent_UserLeft({required this.userId, required this.nickname, required this.reason}): super._();
  

 final  int userId;
 final  String nickname;
 final  String reason;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TsEvent_UserLeftCopyWith<TsEvent_UserLeft> get copyWith => _$TsEvent_UserLeftCopyWithImpl<TsEvent_UserLeft>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TsEvent_UserLeft&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.nickname, nickname) || other.nickname == nickname)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,userId,nickname,reason);

@override
String toString() {
  return 'TsEvent.userLeft(userId: $userId, nickname: $nickname, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $TsEvent_UserLeftCopyWith<$Res> implements $TsEventCopyWith<$Res> {
  factory $TsEvent_UserLeftCopyWith(TsEvent_UserLeft value, $Res Function(TsEvent_UserLeft) _then) = _$TsEvent_UserLeftCopyWithImpl;
@useResult
$Res call({
 int userId, String nickname, String reason
});




}
/// @nodoc
class _$TsEvent_UserLeftCopyWithImpl<$Res>
    implements $TsEvent_UserLeftCopyWith<$Res> {
  _$TsEvent_UserLeftCopyWithImpl(this._self, this._then);

  final TsEvent_UserLeft _self;
  final $Res Function(TsEvent_UserLeft) _then;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? userId = null,Object? nickname = null,Object? reason = null,}) {
  return _then(TsEvent_UserLeft(
userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as int,nickname: null == nickname ? _self.nickname : nickname // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class TsEvent_UserMoved extends TsEvent {
  const TsEvent_UserMoved({required this.userId, required this.nickname, required this.fromChannel, required this.toChannel}): super._();
  

 final  int userId;
 final  String nickname;
 final  PlatformInt64 fromChannel;
 final  PlatformInt64 toChannel;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TsEvent_UserMovedCopyWith<TsEvent_UserMoved> get copyWith => _$TsEvent_UserMovedCopyWithImpl<TsEvent_UserMoved>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TsEvent_UserMoved&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.nickname, nickname) || other.nickname == nickname)&&(identical(other.fromChannel, fromChannel) || other.fromChannel == fromChannel)&&(identical(other.toChannel, toChannel) || other.toChannel == toChannel));
}


@override
int get hashCode => Object.hash(runtimeType,userId,nickname,fromChannel,toChannel);

@override
String toString() {
  return 'TsEvent.userMoved(userId: $userId, nickname: $nickname, fromChannel: $fromChannel, toChannel: $toChannel)';
}


}

/// @nodoc
abstract mixin class $TsEvent_UserMovedCopyWith<$Res> implements $TsEventCopyWith<$Res> {
  factory $TsEvent_UserMovedCopyWith(TsEvent_UserMoved value, $Res Function(TsEvent_UserMoved) _then) = _$TsEvent_UserMovedCopyWithImpl;
@useResult
$Res call({
 int userId, String nickname, PlatformInt64 fromChannel, PlatformInt64 toChannel
});




}
/// @nodoc
class _$TsEvent_UserMovedCopyWithImpl<$Res>
    implements $TsEvent_UserMovedCopyWith<$Res> {
  _$TsEvent_UserMovedCopyWithImpl(this._self, this._then);

  final TsEvent_UserMoved _self;
  final $Res Function(TsEvent_UserMoved) _then;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? userId = null,Object? nickname = null,Object? fromChannel = null,Object? toChannel = null,}) {
  return _then(TsEvent_UserMoved(
userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as int,nickname: null == nickname ? _self.nickname : nickname // ignore: cast_nullable_to_non_nullable
as String,fromChannel: null == fromChannel ? _self.fromChannel : fromChannel // ignore: cast_nullable_to_non_nullable
as PlatformInt64,toChannel: null == toChannel ? _self.toChannel : toChannel // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class TsEvent_UserKickedFromChannel extends TsEvent {
  const TsEvent_UserKickedFromChannel({required this.userId, required this.kickerId, required this.reason}): super._();
  

 final  int userId;
 final  int kickerId;
 final  String reason;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TsEvent_UserKickedFromChannelCopyWith<TsEvent_UserKickedFromChannel> get copyWith => _$TsEvent_UserKickedFromChannelCopyWithImpl<TsEvent_UserKickedFromChannel>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TsEvent_UserKickedFromChannel&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.kickerId, kickerId) || other.kickerId == kickerId)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,userId,kickerId,reason);

@override
String toString() {
  return 'TsEvent.userKickedFromChannel(userId: $userId, kickerId: $kickerId, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $TsEvent_UserKickedFromChannelCopyWith<$Res> implements $TsEventCopyWith<$Res> {
  factory $TsEvent_UserKickedFromChannelCopyWith(TsEvent_UserKickedFromChannel value, $Res Function(TsEvent_UserKickedFromChannel) _then) = _$TsEvent_UserKickedFromChannelCopyWithImpl;
@useResult
$Res call({
 int userId, int kickerId, String reason
});




}
/// @nodoc
class _$TsEvent_UserKickedFromChannelCopyWithImpl<$Res>
    implements $TsEvent_UserKickedFromChannelCopyWith<$Res> {
  _$TsEvent_UserKickedFromChannelCopyWithImpl(this._self, this._then);

  final TsEvent_UserKickedFromChannel _self;
  final $Res Function(TsEvent_UserKickedFromChannel) _then;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? userId = null,Object? kickerId = null,Object? reason = null,}) {
  return _then(TsEvent_UserKickedFromChannel(
userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as int,kickerId: null == kickerId ? _self.kickerId : kickerId // ignore: cast_nullable_to_non_nullable
as int,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class TsEvent_UserKickedFromServer extends TsEvent {
  const TsEvent_UserKickedFromServer({required this.userId, required this.kickerId, required this.reason}): super._();
  

 final  int userId;
 final  int kickerId;
 final  String reason;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TsEvent_UserKickedFromServerCopyWith<TsEvent_UserKickedFromServer> get copyWith => _$TsEvent_UserKickedFromServerCopyWithImpl<TsEvent_UserKickedFromServer>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TsEvent_UserKickedFromServer&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.kickerId, kickerId) || other.kickerId == kickerId)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,userId,kickerId,reason);

@override
String toString() {
  return 'TsEvent.userKickedFromServer(userId: $userId, kickerId: $kickerId, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $TsEvent_UserKickedFromServerCopyWith<$Res> implements $TsEventCopyWith<$Res> {
  factory $TsEvent_UserKickedFromServerCopyWith(TsEvent_UserKickedFromServer value, $Res Function(TsEvent_UserKickedFromServer) _then) = _$TsEvent_UserKickedFromServerCopyWithImpl;
@useResult
$Res call({
 int userId, int kickerId, String reason
});




}
/// @nodoc
class _$TsEvent_UserKickedFromServerCopyWithImpl<$Res>
    implements $TsEvent_UserKickedFromServerCopyWith<$Res> {
  _$TsEvent_UserKickedFromServerCopyWithImpl(this._self, this._then);

  final TsEvent_UserKickedFromServer _self;
  final $Res Function(TsEvent_UserKickedFromServer) _then;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? userId = null,Object? kickerId = null,Object? reason = null,}) {
  return _then(TsEvent_UserKickedFromServer(
userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as int,kickerId: null == kickerId ? _self.kickerId : kickerId // ignore: cast_nullable_to_non_nullable
as int,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class TsEvent_UserBanned extends TsEvent {
  const TsEvent_UserBanned({required this.userId, required this.bannerId, required this.reason}): super._();
  

 final  int userId;
 final  int bannerId;
 final  String reason;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TsEvent_UserBannedCopyWith<TsEvent_UserBanned> get copyWith => _$TsEvent_UserBannedCopyWithImpl<TsEvent_UserBanned>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TsEvent_UserBanned&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.bannerId, bannerId) || other.bannerId == bannerId)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,userId,bannerId,reason);

@override
String toString() {
  return 'TsEvent.userBanned(userId: $userId, bannerId: $bannerId, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $TsEvent_UserBannedCopyWith<$Res> implements $TsEventCopyWith<$Res> {
  factory $TsEvent_UserBannedCopyWith(TsEvent_UserBanned value, $Res Function(TsEvent_UserBanned) _then) = _$TsEvent_UserBannedCopyWithImpl;
@useResult
$Res call({
 int userId, int bannerId, String reason
});




}
/// @nodoc
class _$TsEvent_UserBannedCopyWithImpl<$Res>
    implements $TsEvent_UserBannedCopyWith<$Res> {
  _$TsEvent_UserBannedCopyWithImpl(this._self, this._then);

  final TsEvent_UserBanned _self;
  final $Res Function(TsEvent_UserBanned) _then;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? userId = null,Object? bannerId = null,Object? reason = null,}) {
  return _then(TsEvent_UserBanned(
userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as int,bannerId: null == bannerId ? _self.bannerId : bannerId // ignore: cast_nullable_to_non_nullable
as int,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class TsEvent_UserUpdated extends TsEvent {
  const TsEvent_UserUpdated({required this.userId, required this.nickname}): super._();
  

 final  int userId;
 final  String nickname;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TsEvent_UserUpdatedCopyWith<TsEvent_UserUpdated> get copyWith => _$TsEvent_UserUpdatedCopyWithImpl<TsEvent_UserUpdated>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TsEvent_UserUpdated&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.nickname, nickname) || other.nickname == nickname));
}


@override
int get hashCode => Object.hash(runtimeType,userId,nickname);

@override
String toString() {
  return 'TsEvent.userUpdated(userId: $userId, nickname: $nickname)';
}


}

/// @nodoc
abstract mixin class $TsEvent_UserUpdatedCopyWith<$Res> implements $TsEventCopyWith<$Res> {
  factory $TsEvent_UserUpdatedCopyWith(TsEvent_UserUpdated value, $Res Function(TsEvent_UserUpdated) _then) = _$TsEvent_UserUpdatedCopyWithImpl;
@useResult
$Res call({
 int userId, String nickname
});




}
/// @nodoc
class _$TsEvent_UserUpdatedCopyWithImpl<$Res>
    implements $TsEvent_UserUpdatedCopyWith<$Res> {
  _$TsEvent_UserUpdatedCopyWithImpl(this._self, this._then);

  final TsEvent_UserUpdated _self;
  final $Res Function(TsEvent_UserUpdated) _then;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? userId = null,Object? nickname = null,}) {
  return _then(TsEvent_UserUpdated(
userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as int,nickname: null == nickname ? _self.nickname : nickname // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class TsEvent_TalkStatusStart extends TsEvent {
  const TsEvent_TalkStatusStart({required this.userId}): super._();
  

 final  int userId;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TsEvent_TalkStatusStartCopyWith<TsEvent_TalkStatusStart> get copyWith => _$TsEvent_TalkStatusStartCopyWithImpl<TsEvent_TalkStatusStart>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TsEvent_TalkStatusStart&&(identical(other.userId, userId) || other.userId == userId));
}


@override
int get hashCode => Object.hash(runtimeType,userId);

@override
String toString() {
  return 'TsEvent.talkStatusStart(userId: $userId)';
}


}

/// @nodoc
abstract mixin class $TsEvent_TalkStatusStartCopyWith<$Res> implements $TsEventCopyWith<$Res> {
  factory $TsEvent_TalkStatusStartCopyWith(TsEvent_TalkStatusStart value, $Res Function(TsEvent_TalkStatusStart) _then) = _$TsEvent_TalkStatusStartCopyWithImpl;
@useResult
$Res call({
 int userId
});




}
/// @nodoc
class _$TsEvent_TalkStatusStartCopyWithImpl<$Res>
    implements $TsEvent_TalkStatusStartCopyWith<$Res> {
  _$TsEvent_TalkStatusStartCopyWithImpl(this._self, this._then);

  final TsEvent_TalkStatusStart _self;
  final $Res Function(TsEvent_TalkStatusStart) _then;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? userId = null,}) {
  return _then(TsEvent_TalkStatusStart(
userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class TsEvent_TalkStatusStop extends TsEvent {
  const TsEvent_TalkStatusStop({required this.userId}): super._();
  

 final  int userId;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TsEvent_TalkStatusStopCopyWith<TsEvent_TalkStatusStop> get copyWith => _$TsEvent_TalkStatusStopCopyWithImpl<TsEvent_TalkStatusStop>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TsEvent_TalkStatusStop&&(identical(other.userId, userId) || other.userId == userId));
}


@override
int get hashCode => Object.hash(runtimeType,userId);

@override
String toString() {
  return 'TsEvent.talkStatusStop(userId: $userId)';
}


}

/// @nodoc
abstract mixin class $TsEvent_TalkStatusStopCopyWith<$Res> implements $TsEventCopyWith<$Res> {
  factory $TsEvent_TalkStatusStopCopyWith(TsEvent_TalkStatusStop value, $Res Function(TsEvent_TalkStatusStop) _then) = _$TsEvent_TalkStatusStopCopyWithImpl;
@useResult
$Res call({
 int userId
});




}
/// @nodoc
class _$TsEvent_TalkStatusStopCopyWithImpl<$Res>
    implements $TsEvent_TalkStatusStopCopyWith<$Res> {
  _$TsEvent_TalkStatusStopCopyWithImpl(this._self, this._then);

  final TsEvent_TalkStatusStop _self;
  final $Res Function(TsEvent_TalkStatusStop) _then;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? userId = null,}) {
  return _then(TsEvent_TalkStatusStop(
userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class TsEvent_TextMessage extends TsEvent {
  const TsEvent_TextMessage({required this.senderId, required this.senderName, required this.message, required this.target}): super._();
  

 final  int senderId;
 final  String senderName;
 final  String message;
 final  TsMessageTarget target;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TsEvent_TextMessageCopyWith<TsEvent_TextMessage> get copyWith => _$TsEvent_TextMessageCopyWithImpl<TsEvent_TextMessage>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TsEvent_TextMessage&&(identical(other.senderId, senderId) || other.senderId == senderId)&&(identical(other.senderName, senderName) || other.senderName == senderName)&&(identical(other.message, message) || other.message == message)&&(identical(other.target, target) || other.target == target));
}


@override
int get hashCode => Object.hash(runtimeType,senderId,senderName,message,target);

@override
String toString() {
  return 'TsEvent.textMessage(senderId: $senderId, senderName: $senderName, message: $message, target: $target)';
}


}

/// @nodoc
abstract mixin class $TsEvent_TextMessageCopyWith<$Res> implements $TsEventCopyWith<$Res> {
  factory $TsEvent_TextMessageCopyWith(TsEvent_TextMessage value, $Res Function(TsEvent_TextMessage) _then) = _$TsEvent_TextMessageCopyWithImpl;
@useResult
$Res call({
 int senderId, String senderName, String message, TsMessageTarget target
});




}
/// @nodoc
class _$TsEvent_TextMessageCopyWithImpl<$Res>
    implements $TsEvent_TextMessageCopyWith<$Res> {
  _$TsEvent_TextMessageCopyWithImpl(this._self, this._then);

  final TsEvent_TextMessage _self;
  final $Res Function(TsEvent_TextMessage) _then;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? senderId = null,Object? senderName = null,Object? message = null,Object? target = null,}) {
  return _then(TsEvent_TextMessage(
senderId: null == senderId ? _self.senderId : senderId // ignore: cast_nullable_to_non_nullable
as int,senderName: null == senderName ? _self.senderName : senderName // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,target: null == target ? _self.target : target // ignore: cast_nullable_to_non_nullable
as TsMessageTarget,
  ));
}


}

/// @nodoc


class TsEvent_Poked extends TsEvent {
  const TsEvent_Poked({required this.pokerId, required this.pokerName, required this.message}): super._();
  

 final  int pokerId;
 final  String pokerName;
 final  String message;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TsEvent_PokedCopyWith<TsEvent_Poked> get copyWith => _$TsEvent_PokedCopyWithImpl<TsEvent_Poked>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TsEvent_Poked&&(identical(other.pokerId, pokerId) || other.pokerId == pokerId)&&(identical(other.pokerName, pokerName) || other.pokerName == pokerName)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,pokerId,pokerName,message);

@override
String toString() {
  return 'TsEvent.poked(pokerId: $pokerId, pokerName: $pokerName, message: $message)';
}


}

/// @nodoc
abstract mixin class $TsEvent_PokedCopyWith<$Res> implements $TsEventCopyWith<$Res> {
  factory $TsEvent_PokedCopyWith(TsEvent_Poked value, $Res Function(TsEvent_Poked) _then) = _$TsEvent_PokedCopyWithImpl;
@useResult
$Res call({
 int pokerId, String pokerName, String message
});




}
/// @nodoc
class _$TsEvent_PokedCopyWithImpl<$Res>
    implements $TsEvent_PokedCopyWith<$Res> {
  _$TsEvent_PokedCopyWithImpl(this._self, this._then);

  final TsEvent_Poked _self;
  final $Res Function(TsEvent_Poked) _then;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? pokerId = null,Object? pokerName = null,Object? message = null,}) {
  return _then(TsEvent_Poked(
pokerId: null == pokerId ? _self.pokerId : pokerId // ignore: cast_nullable_to_non_nullable
as int,pokerName: null == pokerName ? _self.pokerName : pokerName // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class TsEvent_CommandError extends TsEvent {
  const TsEvent_CommandError({required this.errorId, required this.message}): super._();
  

 final  int errorId;
 final  String message;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TsEvent_CommandErrorCopyWith<TsEvent_CommandError> get copyWith => _$TsEvent_CommandErrorCopyWithImpl<TsEvent_CommandError>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TsEvent_CommandError&&(identical(other.errorId, errorId) || other.errorId == errorId)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,errorId,message);

@override
String toString() {
  return 'TsEvent.commandError(errorId: $errorId, message: $message)';
}


}

/// @nodoc
abstract mixin class $TsEvent_CommandErrorCopyWith<$Res> implements $TsEventCopyWith<$Res> {
  factory $TsEvent_CommandErrorCopyWith(TsEvent_CommandError value, $Res Function(TsEvent_CommandError) _then) = _$TsEvent_CommandErrorCopyWithImpl;
@useResult
$Res call({
 int errorId, String message
});




}
/// @nodoc
class _$TsEvent_CommandErrorCopyWithImpl<$Res>
    implements $TsEvent_CommandErrorCopyWith<$Res> {
  _$TsEvent_CommandErrorCopyWithImpl(this._self, this._then);

  final TsEvent_CommandError _self;
  final $Res Function(TsEvent_CommandError) _then;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? errorId = null,Object? message = null,}) {
  return _then(TsEvent_CommandError(
errorId: null == errorId ? _self.errorId : errorId // ignore: cast_nullable_to_non_nullable
as int,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class TsEvent_ChannelPermissionsUpdated extends TsEvent {
  const TsEvent_ChannelPermissionsUpdated({required this.channelId, required this.permissionHints}): super._();
  

 final  PlatformInt64 channelId;
 final  PlatformInt64 permissionHints;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TsEvent_ChannelPermissionsUpdatedCopyWith<TsEvent_ChannelPermissionsUpdated> get copyWith => _$TsEvent_ChannelPermissionsUpdatedCopyWithImpl<TsEvent_ChannelPermissionsUpdated>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TsEvent_ChannelPermissionsUpdated&&(identical(other.channelId, channelId) || other.channelId == channelId)&&(identical(other.permissionHints, permissionHints) || other.permissionHints == permissionHints));
}


@override
int get hashCode => Object.hash(runtimeType,channelId,permissionHints);

@override
String toString() {
  return 'TsEvent.channelPermissionsUpdated(channelId: $channelId, permissionHints: $permissionHints)';
}


}

/// @nodoc
abstract mixin class $TsEvent_ChannelPermissionsUpdatedCopyWith<$Res> implements $TsEventCopyWith<$Res> {
  factory $TsEvent_ChannelPermissionsUpdatedCopyWith(TsEvent_ChannelPermissionsUpdated value, $Res Function(TsEvent_ChannelPermissionsUpdated) _then) = _$TsEvent_ChannelPermissionsUpdatedCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 channelId, PlatformInt64 permissionHints
});




}
/// @nodoc
class _$TsEvent_ChannelPermissionsUpdatedCopyWithImpl<$Res>
    implements $TsEvent_ChannelPermissionsUpdatedCopyWith<$Res> {
  _$TsEvent_ChannelPermissionsUpdatedCopyWithImpl(this._self, this._then);

  final TsEvent_ChannelPermissionsUpdated _self;
  final $Res Function(TsEvent_ChannelPermissionsUpdated) _then;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? channelId = null,Object? permissionHints = null,}) {
  return _then(TsEvent_ChannelPermissionsUpdated(
channelId: null == channelId ? _self.channelId : channelId // ignore: cast_nullable_to_non_nullable
as PlatformInt64,permissionHints: null == permissionHints ? _self.permissionHints : permissionHints // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class TsEvent_StreamsChanged extends TsEvent {
  const TsEvent_StreamsChanged({required final  List<TsStream> streams}): _streams = streams,super._();
  

 final  List<TsStream> _streams;
 List<TsStream> get streams {
  if (_streams is EqualUnmodifiableListView) return _streams;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_streams);
}


/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TsEvent_StreamsChangedCopyWith<TsEvent_StreamsChanged> get copyWith => _$TsEvent_StreamsChangedCopyWithImpl<TsEvent_StreamsChanged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TsEvent_StreamsChanged&&const DeepCollectionEquality().equals(other._streams, _streams));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_streams));

@override
String toString() {
  return 'TsEvent.streamsChanged(streams: $streams)';
}


}

/// @nodoc
abstract mixin class $TsEvent_StreamsChangedCopyWith<$Res> implements $TsEventCopyWith<$Res> {
  factory $TsEvent_StreamsChangedCopyWith(TsEvent_StreamsChanged value, $Res Function(TsEvent_StreamsChanged) _then) = _$TsEvent_StreamsChangedCopyWithImpl;
@useResult
$Res call({
 List<TsStream> streams
});




}
/// @nodoc
class _$TsEvent_StreamsChangedCopyWithImpl<$Res>
    implements $TsEvent_StreamsChangedCopyWith<$Res> {
  _$TsEvent_StreamsChangedCopyWithImpl(this._self, this._then);

  final TsEvent_StreamsChanged _self;
  final $Res Function(TsEvent_StreamsChanged) _then;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? streams = null,}) {
  return _then(TsEvent_StreamsChanged(
streams: null == streams ? _self._streams : streams // ignore: cast_nullable_to_non_nullable
as List<TsStream>,
  ));
}


}

/// @nodoc


class TsEvent_StreamJoinResponse extends TsEvent {
  const TsEvent_StreamJoinResponse({required this.ownerId, required this.streamId, required this.accepted, this.message, this.offer}): super._();
  

 final  int ownerId;
 final  String streamId;
 final  bool accepted;
 final  String? message;
 final  String? offer;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TsEvent_StreamJoinResponseCopyWith<TsEvent_StreamJoinResponse> get copyWith => _$TsEvent_StreamJoinResponseCopyWithImpl<TsEvent_StreamJoinResponse>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TsEvent_StreamJoinResponse&&(identical(other.ownerId, ownerId) || other.ownerId == ownerId)&&(identical(other.streamId, streamId) || other.streamId == streamId)&&(identical(other.accepted, accepted) || other.accepted == accepted)&&(identical(other.message, message) || other.message == message)&&(identical(other.offer, offer) || other.offer == offer));
}


@override
int get hashCode => Object.hash(runtimeType,ownerId,streamId,accepted,message,offer);

@override
String toString() {
  return 'TsEvent.streamJoinResponse(ownerId: $ownerId, streamId: $streamId, accepted: $accepted, message: $message, offer: $offer)';
}


}

/// @nodoc
abstract mixin class $TsEvent_StreamJoinResponseCopyWith<$Res> implements $TsEventCopyWith<$Res> {
  factory $TsEvent_StreamJoinResponseCopyWith(TsEvent_StreamJoinResponse value, $Res Function(TsEvent_StreamJoinResponse) _then) = _$TsEvent_StreamJoinResponseCopyWithImpl;
@useResult
$Res call({
 int ownerId, String streamId, bool accepted, String? message, String? offer
});




}
/// @nodoc
class _$TsEvent_StreamJoinResponseCopyWithImpl<$Res>
    implements $TsEvent_StreamJoinResponseCopyWith<$Res> {
  _$TsEvent_StreamJoinResponseCopyWithImpl(this._self, this._then);

  final TsEvent_StreamJoinResponse _self;
  final $Res Function(TsEvent_StreamJoinResponse) _then;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? ownerId = null,Object? streamId = null,Object? accepted = null,Object? message = freezed,Object? offer = freezed,}) {
  return _then(TsEvent_StreamJoinResponse(
ownerId: null == ownerId ? _self.ownerId : ownerId // ignore: cast_nullable_to_non_nullable
as int,streamId: null == streamId ? _self.streamId : streamId // ignore: cast_nullable_to_non_nullable
as String,accepted: null == accepted ? _self.accepted : accepted // ignore: cast_nullable_to_non_nullable
as bool,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,offer: freezed == offer ? _self.offer : offer // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class TsEvent_StreamSignaling extends TsEvent {
  const TsEvent_StreamSignaling({required this.ownerId, required this.streamId, required this.json}): super._();
  

 final  int ownerId;
 final  String streamId;
 final  String json;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TsEvent_StreamSignalingCopyWith<TsEvent_StreamSignaling> get copyWith => _$TsEvent_StreamSignalingCopyWithImpl<TsEvent_StreamSignaling>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TsEvent_StreamSignaling&&(identical(other.ownerId, ownerId) || other.ownerId == ownerId)&&(identical(other.streamId, streamId) || other.streamId == streamId)&&(identical(other.json, json) || other.json == json));
}


@override
int get hashCode => Object.hash(runtimeType,ownerId,streamId,json);

@override
String toString() {
  return 'TsEvent.streamSignaling(ownerId: $ownerId, streamId: $streamId, json: $json)';
}


}

/// @nodoc
abstract mixin class $TsEvent_StreamSignalingCopyWith<$Res> implements $TsEventCopyWith<$Res> {
  factory $TsEvent_StreamSignalingCopyWith(TsEvent_StreamSignaling value, $Res Function(TsEvent_StreamSignaling) _then) = _$TsEvent_StreamSignalingCopyWithImpl;
@useResult
$Res call({
 int ownerId, String streamId, String json
});




}
/// @nodoc
class _$TsEvent_StreamSignalingCopyWithImpl<$Res>
    implements $TsEvent_StreamSignalingCopyWith<$Res> {
  _$TsEvent_StreamSignalingCopyWithImpl(this._self, this._then);

  final TsEvent_StreamSignaling _self;
  final $Res Function(TsEvent_StreamSignaling) _then;

/// Create a copy of TsEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? ownerId = null,Object? streamId = null,Object? json = null,}) {
  return _then(TsEvent_StreamSignaling(
ownerId: null == ownerId ? _self.ownerId : ownerId // ignore: cast_nullable_to_non_nullable
as int,streamId: null == streamId ? _self.streamId : streamId // ignore: cast_nullable_to_non_nullable
as String,json: null == json ? _self.json : json // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
