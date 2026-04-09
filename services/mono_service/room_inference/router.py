import asyncio

from fastapi import APIRouter, File, UploadFile

from . import infer

router = APIRouter(prefix='/room-inference')


@router.post('')
async def room_inference(file: UploadFile = File(...)):
    image_bytes = await file.read()
    async with infer.semaphore:
        loop = asyncio.get_event_loop()
        result = await loop.run_in_executor(infer.executor, infer.run, image_bytes)
    return result
