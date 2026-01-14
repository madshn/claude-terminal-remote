# ntfy Issue Draft (iOS Feature Request)

**Status:** ✅ POSTED - https://github.com/binwiederhier/ntfy/issues/1546

**Repository:** https://github.com/binwiederhier/ntfy-ios (for PR)

> Note: iOS issues are typically filed on the main ntfy repo, but PRs go to ntfy-ios

---

## Title

Feature Request: Register UNNotificationCategory for native iOS notification actions + Apple Watch support

## Labels

`enhancement`, `ios-app` (check existing labels on the repo)

## Body

### Summary

Action buttons currently only appear inside the ntfy app. By registering `UNNotificationCategory` with `UNNotificationAction`, buttons would appear as native iOS notification actions AND automatically mirror to Apple Watch.

### Current Behavior

- Action buttons: ✅ Visible in ntfy app message detail view
- Action buttons: ❌ NOT visible in iOS Notification Center (swipe/long-press)
- Action buttons: ❌ NOT visible on Apple Watch (only "Dismiss" shown)

### Expected Behavior

When a notification with actions arrives:
1. Swiping/long-pressing the notification in iOS shows action buttons
2. Apple Watch shows action buttons (up to 4, first 2 in compact view)
3. Tapping an action triggers the HTTP request directly from notification

### Technical Approach

1. Register `UNNotificationCategory` for notifications containing actions
2. Create `UNNotificationAction` instances for each action (view, http)
3. Include the `category` identifier in the push payload
4. iOS will display actions in Notification Center
5. watchOS will automatically mirror actions without needing a watchOS app

### Why This Matters

- **Speed**: Respond to notifications without opening the app
- **Apple Watch**: Huge UX improvement - respond from wrist
- **Consistency**: Match Android behavior where actions appear in notification shade

### References

- [Apple: Declaring actionable notification types](https://developer.apple.com/documentation/usernotifications/declaring-your-actionable-notification-types)
- [Apple: Adding actions to notifications on watchOS](https://developer.apple.com/documentation/watchos-apps/adding-actions-to-notifications-on-watchos)
- Related: #1156 (action button clear not working - may be connected)
