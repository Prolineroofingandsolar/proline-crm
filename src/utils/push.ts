const VAPID_PUBLIC_KEY = 'BK03ElAcOOzgwT4bjpm1ZEjefRgzWvQg-G0MgGEcOF5EfEjfWLNLQ2NUPwAfLX2qneu2f_iFvVUlNYrPWMYuoaw';

export type DeviceNotificationPermission = 'granted' | 'denied' | 'default' | 'unsupported';

export function isMacApp(): boolean {
  return typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;
}

function urlBase64ToUint8Array(base64String: string): Uint8Array<ArrayBuffer> {
  const padding = '='.repeat((4 - base64String.length % 4) % 4);
  const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
  const rawData = window.atob(base64);
  const output = new Uint8Array(rawData.length);
  for (let i = 0; i < rawData.length; i++) output[i] = rawData.charCodeAt(i);
  return output;
}

export async function getDeviceNotificationPermission(): Promise<DeviceNotificationPermission> {
  if (isMacApp()) {
    const { isPermissionGranted } = await import('@tauri-apps/plugin-notification');
    return (await isPermissionGranted()) ? 'granted' : 'default';
  }
  if (!('Notification' in window)) return 'unsupported';
  return Notification.permission;
}

export async function enableDeviceNotifications(): Promise<{
  enabled: boolean;
  denied: boolean;
  native: boolean;
  subscription: PushSubscription | null;
}> {
  if (isMacApp()) {
    const { isPermissionGranted, requestPermission } = await import('@tauri-apps/plugin-notification');
    let granted = await isPermissionGranted();
    let denied = false;
    if (!granted) {
      const permission = await requestPermission();
      granted = permission === 'granted';
      denied = permission === 'denied';
    }
    return { enabled: granted, denied, native: true, subscription: null };
  }

  if (!('serviceWorker' in navigator) || !('PushManager' in window) || !('Notification' in window)) {
    return { enabled: false, denied: false, native: false, subscription: null };
  }
  const reg = await navigator.serviceWorker.ready;
  const permission = await Notification.requestPermission();
  if (permission !== 'granted') return { enabled: false, denied: permission === 'denied', native: false, subscription: null };
  try {
    const subscription = await reg.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: urlBase64ToUint8Array(VAPID_PUBLIC_KEY),
    });
    return { enabled: true, denied: false, native: false, subscription };
  } catch {
    return { enabled: false, denied: false, native: false, subscription: null };
  }
}

export async function sendDeviceNotification(title: string, body: string): Promise<void> {
  if (!isMacApp()) return;
  const { isPermissionGranted, sendNotification } = await import('@tauri-apps/plugin-notification');
  if (await isPermissionGranted()) {
    sendNotification({ title, body, sound: 'default', group: 'proline-crm' });
  }
}
