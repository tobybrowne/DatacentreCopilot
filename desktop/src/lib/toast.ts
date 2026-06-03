import { writable } from "svelte/store";

export type ToastType = "error" | "success" | "info";

export interface ToastItem {
  id: number;
  message: string;
  type: ToastType;
}

const { subscribe, update } = writable<ToastItem[]>([]);

export const toasts = { subscribe };

let nextId = 0;

export function toast(message: string, type: ToastType = "error"): void {
  const id = nextId++;
  update((list) => [...list, { id, message, type }]);
  setTimeout(() => dismiss(id), 4500);
}

export function dismiss(id: number): void {
  update((list) => list.filter((t) => t.id !== id));
}
