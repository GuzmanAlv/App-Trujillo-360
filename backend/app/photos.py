"""Validate actual image contents and remove metadata before server storage."""
import base64
import binascii
import hashlib
import io
import warnings
from uuid import UUID
from PIL import Image, ImageOps, UnidentifiedImageError
from pydantic import BaseModel, ConfigDict, Field

MAX_PHOTO_BYTES = 2 * 1024 * 1024
MAX_PHOTO_PIXELS = 12_000_000


class PhotoInput(BaseModel):
    model_config = ConfigDict(extra='forbid')
    id: UUID
    content_base64: str = Field(min_length=4, max_length=4 * ((MAX_PHOTO_BYTES + 2) // 3))


def normalize_photo(photo: PhotoInput):
    try:
        raw = base64.b64decode(photo.content_base64, validate=True)
        if not raw or len(raw) > MAX_PHOTO_BYTES:
            raise ValueError('Foto demasiado grande')
        with warnings.catch_warnings():
            warnings.simplefilter('error', Image.DecompressionBombWarning)
            with Image.open(io.BytesIO(raw)) as probe:
                if probe.format not in ('JPEG', 'PNG') or probe.width * probe.height > MAX_PHOTO_PIXELS:
                    raise ValueError('Formato o resolución no permitido')
                if getattr(probe, 'n_frames', 1) != 1:
                    raise ValueError('La foto no puede ser animada')
                probe.verify()
            with Image.open(io.BytesIO(raw)) as image:
                corrected = ImageOps.exif_transpose(image)
                corrected.thumbnail((1600, 1600))
                rgba = corrected.convert('RGBA')
                flattened = Image.new('RGB', rgba.size, 'white')
                flattened.paste(rgba, mask=rgba.getchannel('A'))
                output = io.BytesIO()
                flattened.save(output, format='JPEG', quality=82, optimize=True)
        content = output.getvalue()
        if len(content) > MAX_PHOTO_BYTES:
            raise ValueError('Foto demasiado grande')
        return {'id': str(photo.id), 'sha256': hashlib.sha256(raw).hexdigest(),
                'content_base64': base64.b64encode(content).decode('ascii')}
    except (binascii.Error, UnidentifiedImageError, OSError, SyntaxError,
            Image.DecompressionBombError, Image.DecompressionBombWarning) as error:
        raise ValueError('Foto inválida') from error
