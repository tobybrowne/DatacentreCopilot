import os
import subprocess
import tempfile
from pathlib import Path

from fastapi import APIRouter, BackgroundTasks
from pydantic import BaseModel

from common import get_supabase

router = APIRouter(prefix='/video')

FFMPEG = os.environ.get('FFMPEG_PATH', '/opt/homebrew/opt/ffmpeg-full/bin/ffmpeg')
BUCKET = 'log_bucket'


class ConvertRequest(BaseModel):
    log_id: str


def _convert(log_id: str) -> None:
    sb = get_supabase()

    row = (
        sb.table('logs')
        .select('camera_recording_path')
        .eq('id', log_id)
        .single()
        .execute()
        .data
    )
    if not row or not row.get('camera_recording_path'):
        raise ValueError(f'No camera_recording_path for log {log_id}')

    mp4_remote = row['camera_recording_path']
    ogv_remote = str(Path(mp4_remote).with_suffix('.ogv'))

    with tempfile.TemporaryDirectory() as tmp:
        mp4_path = Path(tmp) / 'input.mp4'
        ogv_path = Path(tmp) / 'output.ogv'

        mp4_path.write_bytes(sb.storage.from_(BUCKET).download(mp4_remote))

        subprocess.run(
            [
                FFMPEG, '-y', '-i', str(mp4_path),
                '-codec:v', 'libtheora', '-qscale:v', '7',
                '-codec:a', 'libvorbis', '-qscale:a', '5',
                str(ogv_path),
            ],
            check=True,
            capture_output=True,
        )

        sb.storage.from_(BUCKET).upload(ogv_remote, ogv_path.read_bytes())

    sb.table('logs').update({'camera_recording_path_ogv': ogv_remote}).eq('id', log_id).execute()
    print(f'[video] converted {mp4_remote} → {ogv_remote}')


@router.post('/convert')
async def convert(req: ConvertRequest, background_tasks: BackgroundTasks) -> dict:
    """Trigger .mp4 → .ogv conversion for a log row. Runs in the background."""
    background_tasks.add_task(_convert, req.log_id)
    return {'status': 'converting', 'log_id': req.log_id}
