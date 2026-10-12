/// The chat surface's own theme.
///
/// `flutter_chat_ui` carries a full theme of its own and ignores most of
/// the surrounding Material theme, so a restyled app still showed its
/// default bubbles and input. Everything the chat draws — bubbles,
/// avatars, names, the input — is set here, in the same zinc palette and
/// on the same radius scale as the rest of the console.
library;

import 'package:flutter/material.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';

import '../../app/theme.dart';

/// What to fall back to for Chinese, which neither Latin face has.
const List<String> _fallback = ['PingFangSF'];

/// Builds the chat theme for the active brightness.
ChatTheme buildChatTheme({required bool isDark}) {
  // Agent messages sit on a tinted surface; your own are inverted so the
  // two sides read apart without needing any colour at all.
  final received = isDark ? Zinc.c800 : Zinc.c100;
  final sent = isDark ? Zinc.c200 : Zinc.c900;
  final onReceived = isDark ? Zinc.c50 : Zinc.c950;
  final onSent = isDark ? Zinc.c950 : Zinc.c50;

  final surface = isDark ? Zinc.c950 : const Color(0xFFFFFFFF);
  final onSurface = isDark ? Zinc.c50 : Zinc.c950;
  final muted = isDark ? Zinc.c400 : Zinc.c500;
  final subtle = isDark ? Zinc.c800 : Zinc.c200;

  TextStyle body(Color color) => TextStyle(
        fontFamily: 'Manrope', fontFamilyFallback: _fallback,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.55,
        color: color,
      );

  // `ChatTheme` is abstract, so one of its subclasses has to be built.
  // Which one barely matters here: every colour and text style below is
  // derived from [isDark] anyway, and the two differ only in the icons,
  // which are drawn in the palette's own colours regardless.
  return DefaultChatTheme(
  backgroundColor: surface,

  primaryColor: sent,
  secondaryColor: received,

  messageBorderRadius: AppRadius.lg,
  // Comfortable without looking like a button.
  messageInsetsHorizontal: 14,
  messageInsetsVertical: 9,
  messageMaxWidth: 620,
  bubbleMargin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),

  sentMessageBodyTextStyle: body(onSent),
  receivedMessageBodyTextStyle: body(onReceived),
  sentMessageBodyBoldTextStyle: body(onSent).copyWith(
    fontWeight: FontWeight.w600,
  ),
  receivedMessageBodyBoldTextStyle: body(onReceived).copyWith(
    fontWeight: FontWeight.w600,
  ),
  sentMessageBodyCodeTextStyle: TextStyle(
    fontFamily: 'GeistMono', fontFamilyFallback: _fallback,
    fontSize: 13,
    height: 1.5,
    color: onSent,
  ),
  receivedMessageBodyCodeTextStyle: TextStyle(
    fontFamily: 'GeistMono', fontFamilyFallback: _fallback,
    fontSize: 13,
    height: 1.5,
    color: onReceived,
  ),
  sentMessageBodyLinkTextStyle: body(onSent).copyWith(
    decoration: TextDecoration.underline,
  ),
  receivedMessageBodyLinkTextStyle: body(onReceived).copyWith(
    decoration: TextDecoration.underline,
  ),
  sentMessageCaptionTextStyle: body(onSent.withValues(alpha: 0.7))
      .copyWith(fontSize: 12),
  receivedMessageCaptionTextStyle: body(onReceived.withValues(alpha: 0.7))
      .copyWith(fontSize: 12),
  sentMessageLinkTitleTextStyle: body(onSent).copyWith(
    fontSize: 14,
    fontWeight: FontWeight.w600,
  ),
  receivedMessageLinkTitleTextStyle: body(onReceived).copyWith(
    fontSize: 14,
    fontWeight: FontWeight.w600,
  ),
  sentMessageLinkDescriptionTextStyle:
      body(onSent.withValues(alpha: 0.75)).copyWith(fontSize: 12),
  receivedMessageLinkDescriptionTextStyle:
      body(onReceived.withValues(alpha: 0.75)).copyWith(fontSize: 12),
  sentEmojiMessageTextStyle: const TextStyle(fontSize: 34),
  receivedEmojiMessageTextStyle: const TextStyle(fontSize: 34),

  // Shown above a bubble when a conversation has more than one
  // participant — small, muted, and never competing with the message.
  userNameTextStyle: TextStyle(
    fontFamily: 'Manrope', fontFamilyFallback: _fallback,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: muted,
  ),

  sentMessageDocumentIconColor: onSent,
  receivedMessageDocumentIconColor: onReceived,

  // Avatar chips default to a rainbow; pin them to the palette so a
  // name initial is not the most colourful thing on screen.
  userAvatarImageBackgroundColor: Colors.transparent,
  userAvatarNameColors: [isDark ? Zinc.c700 : Zinc.c800],
  userAvatarTextStyle: TextStyle(
    fontFamily: 'Manrope', fontFamilyFallback: _fallback,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: isDark ? Zinc.c50 : Zinc.c50,
  ),

  dateDividerMargin: const EdgeInsets.only(top: 16, bottom: 16),
  dateDividerTextStyle: TextStyle(
    fontFamily: 'GeistMono', fontFamilyFallback: _fallback,
    fontSize: 10,
    fontWeight: FontWeight.w500,
    letterSpacing: 1.1,
    height: 1.3,
    color: muted,
  ),

  emptyChatPlaceholderTextStyle: TextStyle(
    fontFamily: 'Manrope', fontFamilyFallback: _fallback,
    fontSize: 14,
    height: 1.6,
    color: muted,
  ),

  errorColor: isDark ? const Color(0xFFFF6467) : const Color(0xFFE7000B),
  highlightMessageColor: (isDark ? Zinc.c50 : Zinc.c950).withValues(
    alpha: 0.06,
  ),
  statusIconPadding: const EdgeInsets.only(left: 4),

  // ── Input ────────────────────────────────────────────────────
  inputBackgroundColor: isDark ? Zinc.c900 : Zinc.c100,
  inputSurfaceTintColor: Colors.transparent,
  inputElevation: 0,
  inputBorderRadius: BorderRadius.circular(AppRadius.lg),
  inputMargin: const EdgeInsets.fromLTRB(16, 8, 16, 14),
  inputPadding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
  inputTextColor: onSurface,
  inputTextCursorColor: onSurface,
  inputTextStyle: const TextStyle(
    fontFamily: 'Manrope', fontFamilyFallback: _fallback,
    fontSize: 14,
    height: 1.5,
  ),
  inputTextDecoration: InputDecoration(
    filled: false,
    isDense: true,
    contentPadding: EdgeInsets.zero,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    hintStyle: TextStyle(fontFamily: 'Manrope', fontFamilyFallback: _fallback, fontSize: 14, color: muted),
  ),
  inputContainerDecoration: BoxDecoration(
    borderRadius: BorderRadius.circular(AppRadius.lg),
    border: Border.all(color: subtle),
  ),

  systemMessageTheme: SystemMessageTheme(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    textStyle: TextStyle(
      fontFamily: 'Manrope', fontFamilyFallback: _fallback,
      fontSize: 12,
      fontWeight: FontWeight.w500,
      height: 1.4,
      color: muted,
    ),
  ),

  typingIndicatorTheme: TypingIndicatorTheme(
    animatedCirclesColor: muted,
    animatedCircleSize: 4,
    bubbleBorder: const BorderRadius.all(Radius.circular(AppRadius.lg)),
    bubbleColor: received,
    countAvatarColor: sent,
    countTextColor: onSent,
    multipleUserTextStyle: TextStyle(
      fontFamily: 'Manrope', fontFamilyFallback: _fallback,
      fontSize: 11,
      fontWeight: FontWeight.w500,
      color: muted,
    ),
  ),

  unreadHeaderTheme: UnreadHeaderTheme(
    color: subtle.withValues(alpha: 0.5),
    textStyle: TextStyle(
      fontFamily: 'Manrope', fontFamilyFallback: _fallback,
      fontSize: 11,
      fontWeight: FontWeight.w600,
      height: 1.3,
      color: muted,
    ),
  ),
  );
}
