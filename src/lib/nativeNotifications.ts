// Native (iOS/Android) notifications via Capacitor.
//
// Everything here is a safe no-op on the web build — the plugins only do real
// work inside the native app, so the same code powers the website and the app.
import { Capacitor } from '@capacitor/core';
import { LocalNotifications } from '@capacitor/local-notifications';
import { PushNotifications } from '@capacitor/push-notifications';
import { supabase } from './supabase';

export const isNativeApp = () => Capacitor.isNativePlatform();

/**
 * Ask for notification permission and register the device for push.
 * Call once after login (we have the current user id to tie the token to).
 */
export async function initNativeNotifications(currentUserId: string | null) {
  if (!isNativeApp()) return;

  // ── Local notifications ──────────────────────────────────────────────
  try {
    const perm = await LocalNotifications.requestPermissions();
    if (perm.display !== 'granted') return;
    // Tapping a reminder is enough; no custom action types needed yet.
  } catch (e) {
    console.error('Local notification permission error:', e);
  }

  // ── Push notifications (APNs) ────────────────────────────────────────
  try {
    const perm = await PushNotifications.requestPermissions();
    if (perm.receive !== 'granted') return;

    await PushNotifications.register();

    // Fired once iOS hands back the device's APNs token.
    PushNotifications.addListener('registration', async ({ value: token }) => {
      if (!currentUserId) return;
      // Store the token so the backend can send this device pushes.
      const { error } = await supabase.from('push_tokens').upsert(
        {
          token,
          user_id: currentUserId,
          platform: Capacitor.getPlatform(), // 'ios'
          updated_at: new Date().toISOString(),
        },
        { onConflict: 'token' },
      );
      if (error) console.error('Failed to save push token:', error);
    });

    PushNotifications.addListener('registrationError', (err) => {
      console.error('Push registration error:', err);
    });
  } catch (e) {
    console.error('Push notification setup error:', e);
  }
}

interface Remindable {
  id: string;
  title: string;
  dueDate?: string;   // 'YYYY-MM-DD'
  completed: boolean;
}

// Capacitor local-notification ids must be 32-bit ints, so hash the string id.
function numericId(id: string): number {
  let h = 0;
  for (let i = 0; i < id.length; i++) h = (Math.imul(31, h) + id.charCodeAt(i)) | 0;
  return Math.abs(h) % 2_000_000_000;
}

/**
 * Schedule a 9am local reminder on the due date for every incomplete task that
 * has a future due date. Re-schedulable safely — it clears its own pending set
 * first, so calling it again just reflects the latest tasks.
 */
export async function syncTaskReminders(tasks: Remindable[]) {
  if (!isNativeApp()) return;
  try {
    const pending = await LocalNotifications.getPending();
    if (pending.notifications.length) {
      await LocalNotifications.cancel({ notifications: pending.notifications });
    }

    const now = Date.now();
    const toSchedule = tasks
      .filter((t) => !t.completed && t.dueDate)
      .map((t) => {
        const at = new Date(`${t.dueDate}T09:00:00`);
        return { t, at };
      })
      .filter(({ at }) => at.getTime() > now);

    if (!toSchedule.length) return;

    await LocalNotifications.schedule({
      notifications: toSchedule.map(({ t, at }) => ({
        id: numericId(t.id),
        title: 'Task due today',
        body: t.title,
        schedule: { at },
      })),
    });
  } catch (e) {
    console.error('Failed to schedule task reminders:', e);
  }
}
