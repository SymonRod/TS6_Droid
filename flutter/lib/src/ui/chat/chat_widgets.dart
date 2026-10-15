import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../chat/avatars.dart';
import '../../chat/chat_controller.dart';
import '../../chat/chat_models.dart';
import '../theme.dart';

Color presenceColor(BuildContext context, int state) {
  final colors = TsColors.of(context);
  return switch (state) {
    PresenceState.available => colors.talking,
    PresenceState.away => colors.away,
    PresenceState.doNotDisturb => colors.muted,
    _ => Theme.of(context).colorScheme.outline,
  };
}

String presenceLabel(AppLocalizations l, int state) => switch (state) {
  PresenceState.available => l.chatStatusAvailable,
  PresenceState.away => l.chatStatusAway,
  PresenceState.doNotDisturb => l.chatStatusDnd,
  _ => l.chatStatusOffline,
};

IconData presenceIcon(int state) => switch (state) {
  PresenceState.available => Icons.circle,
  PresenceState.away => Icons.schedule,
  PresenceState.doNotDisturb => Icons.do_not_disturb_on,
  _ => Icons.circle_outlined,
};

String chatErrorText(AppLocalizations l, ChatState s) => switch (s.error) {
  ChatError.wrongPassword => l.chatErrWrongPassword,
  ChatError.savedPasswordRejected => l.chatErrSavedPasswordRejected,
  ChatError.network => l.chatErrNetwork,
  ChatError.authentication => l.chatErrAuth,
  ChatError.rateLimited => l.chatErrRateLimited,
  ChatError.server => l.chatErrServer('${s.httpStatus ?? '?'}'),
  ChatError.invalid => l.chatErrInvalid,
  ChatError.loginUncertain => l.chatErrLoginUncertain,
  ChatError.notLoggedIn => l.chatErrNotLoggedIn,
  ChatError.notSendable => l.chatErrNotSendable,
  ChatError.contacts => l.chatErrContacts,
  ChatError.noRecipients => l.chatErrNoRecipients,
  ChatError.unsupportedRoom => l.chatErrUnsupportedRoom,
  ChatError.limit => l.chatErrLimit,
  null => '',
};

String initialsOf(String name) {
  final clean = name.replaceAll(RegExp(r'^@'), '').trim();
  if (clean.isEmpty) return '?';
  return String.fromCharCode(clean.runes.first).toUpperCase();
}

/// Circular avatar: the contact's picture when one loads, else initials or an
/// icon. The optional presence badge never claims a state that isn't known.
class ChatAvatar extends ConsumerWidget {
  final String matrixId;
  final String name;
  final double radius;
  final bool group;
  final int? presence;

  const ChatAvatar({
    super.key,
    required this.matrixId,
    required this.name,
    this.radius = 22,
    this.group = false,
    this.presence,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final bytes = matrixId.isEmpty
        ? null
        : ref.watch(avatarProvider(matrixId)).asData?.value;
    final size = radius * 2;
    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: scheme.secondaryContainer,
      foregroundColor: scheme.onSecondaryContainer,
      foregroundImage: bytes == null
          ? null
          : ResizeImage(
              MemoryImage(bytes),
              width: (size * 2).round(),
              height: (size * 2).round(),
            ),
      onForegroundImageError: bytes == null ? null : (_, _) {},
      child: group
          ? Icon(Icons.group, size: radius)
          : Text(initialsOf(name), style: TextStyle(fontSize: radius * 0.9)),
    );
    if (presence == null) return avatar;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: radius * 0.75,
            height: radius * 0.75,
            decoration: BoxDecoration(
              color: presenceColor(context, presence!),
              shape: BoxShape.circle,
              border: Border.all(color: scheme.surface, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

/// "14:05" today, "Yesterday", else a short date.
String shortTime(BuildContext context, int millis) {
  if (millis <= 0) return '';
  final l = AppLocalizations.of(context);
  final locale = Localizations.localeOf(context).toString();
  final time = DateTime.fromMillisecondsSinceEpoch(millis);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(time.year, time.month, time.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return DateFormat.Hm(locale).format(time);
  if (diff == 1) return l.chatYesterday;
  if (diff < 7) return DateFormat.E(locale).format(time);
  return DateFormat.yMd(locale).format(time);
}

String dayHeading(BuildContext context, int millis) {
  final l = AppLocalizations.of(context);
  final locale = Localizations.localeOf(context).toString();
  final time = DateTime.fromMillisecondsSinceEpoch(millis);
  final now = DateTime.now();
  final diff = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(time.year, time.month, time.day)).inDays;
  if (diff == 0) return l.chatToday;
  if (diff == 1) return l.chatYesterday;
  return DateFormat.yMMMMd(locale).format(time);
}

/// Dismissible error line shown at the top of the chat tabs.
class ChatErrorBanner extends ConsumerWidget {
  const ChatErrorBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(chatProvider);
    if (s.error == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return MaterialBanner(
      backgroundColor: scheme.errorContainer,
      contentTextStyle: TextStyle(color: scheme.onErrorContainer),
      content: Text(chatErrorText(AppLocalizations.of(context), s)),
      actions: [
        if (s.error == ChatError.loginUncertain ||
            s.error == ChatError.notLoggedIn)
          TextButton(
            onPressed: s.refreshing
                ? null
                : ref.read(chatProvider.notifier).retryLogin,
            child: Text(AppLocalizations.of(context).chatRetryLogin),
          ),
        IconButton(
          icon: Icon(Icons.close, color: scheme.onErrorContainer),
          onPressed: ref.read(chatProvider.notifier).clearError,
        ),
      ],
    );
  }
}
