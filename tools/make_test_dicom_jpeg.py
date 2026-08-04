import struct, io
from PIL import Image

def elem_explicit(group, element, vr, value):
    long_vrs = {'OB','OW','OF','OD','OL','SQ','UC','UR','UT','UN'}
    header = struct.pack('<HH', group, element) + vr.encode('ascii')
    if vr in long_vrs:
        header += b'\x00\x00' + struct.pack('<I', len(value))
    else:
        header += struct.pack('<H', len(value))
    return header + value

def elem_implicit_defined(group, element, value):
    return struct.pack('<HH', group, element) + struct.pack('<I', len(value)) + value

def pad_even(b, pad=b' '):
    return b if len(b) % 2 == 0 else b + pad

def us(v):
    return struct.pack('<H', v)

# Build a small grayscale JPEG baseline image with PIL.
img = Image.new('L', (48, 48))
px = img.load()
for y in range(48):
    for x in range(48):
        px[x, y] = (x * 5 + y * 3) % 256
buf = io.BytesIO()
img.save(buf, format='JPEG', quality=90)
jpeg_bytes = buf.getvalue()
if len(jpeg_bytes) % 2 != 0:
    jpeg_bytes += b'\x00'  # pad fragment to even length

transfer_syntax = pad_even(b'1.2.840.10008.1.2.4.50', b'\x00')  # JPEG Baseline

meta_elems = b''
meta_elems += elem_explicit(0x0002, 0x0002, 'UI', pad_even(b'1.2.840.10008.5.1.4.1.1.1.1', b'\x00'))
meta_elems += elem_explicit(0x0002, 0x0003, 'UI', pad_even(b'1.2.3.4.5.6.7.8.9.1', b'\x00'))
meta_elems += elem_explicit(0x0002, 0x0010, 'UI', transfer_syntax)
meta_group_length = elem_explicit(0x0002, 0x0000, 'UL', struct.pack('<I', len(meta_elems)))

# Main dataset: Explicit VR Little Endian (typical when pixel data is compressed)
def elem_ex(group, element, vr, value):
    return elem_explicit(group, element, vr, value)

dataset = b''
dataset += elem_ex(0x0028, 0x0002, 'US', us(1))
dataset += elem_ex(0x0028, 0x0004, 'CS', pad_even(b'MONOCHROME2'))
dataset += elem_ex(0x0028, 0x0010, 'US', us(48))
dataset += elem_ex(0x0028, 0x0011, 'US', us(48))
dataset += elem_ex(0x0028, 0x0100, 'US', us(8))
dataset += elem_ex(0x0028, 0x0101, 'US', us(8))
dataset += elem_ex(0x0028, 0x0103, 'US', us(0))

# Encapsulated Pixel Data (OB, undefined length) -> Basic Offset Table item (empty) + one fragment item
pixel_data_header = struct.pack('<HH', 0x7FE0, 0x0010) + b'OB' + b'\x00\x00' + struct.pack('<I', 0xFFFFFFFF)
offset_table_item = struct.pack('<HH', 0xFFFE, 0xE000) + struct.pack('<I', 0)  # empty basic offset table
fragment_item = struct.pack('<HH', 0xFFFE, 0xE000) + struct.pack('<I', len(jpeg_bytes)) + jpeg_bytes
seq_delim = struct.pack('<HH', 0xFFFE, 0xE0DD) + struct.pack('<I', 0)

dataset += pixel_data_header + offset_table_item + fragment_item + seq_delim

with open(r'C:\Users\arayi\Desktop\Stom\test\fixtures\sample_jpeg.dcm', 'wb') as f:
    f.write(b'\x00' * 128)
    f.write(b'DICM')
    f.write(meta_group_length)
    f.write(meta_elems)
    f.write(dataset)

print("wrote sample_jpeg.dcm, jpeg payload", len(jpeg_bytes), "bytes")
