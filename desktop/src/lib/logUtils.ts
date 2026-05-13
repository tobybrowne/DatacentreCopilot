import type { LogWithContext } from './types'

export function formatDate(iso: string): string {
  return new Date(iso).toLocaleString(undefined, {
    month: 'short', day: 'numeric',
    hour: '2-digit', minute: '2-digit',
  })
}

export function getStepText(log: LogWithContext): string {
  if (!log.step_id || !log.procedureRun?.procedure.steps) return ''
  const step = (log.procedureRun.procedure.steps as { id: string; text: string }[])
    .find(s => s.id === log.step_id)
  return step?.text ?? ''
}
