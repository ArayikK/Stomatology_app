import struct

def elem_explicit(group, element, vr, value):
    long_vrs = {'OB','OW','OF','OD','OL','SQ','UC','UR','UT','UN'}
    header = struct.pack('<HH', group, element) + vr.encode('ascii')
    if vr in long_vrs:
        header += b'\x00\x00' + struct.pack('<I', len(value))
    else:
        header += struct.pack('<H', len(value))
    return header + value

def elem_implicit(group, element, value):
    return struct.pack('<HH', group, element) + struct.pack('<I', len(value)) + value

def pad_even(b, pad=b' '):
    return b if len(b) % 2 == 0 else b + pad

def us(v):
    return struct.pack('<H', v)

# --- File Meta group (always Explicit VR Little Endian) ---
transfer_syntax = pad_even(b'1.2.840.10008.1.2', b'\x00')  # Implicit VR Little Endian
meta_elems = b''
meta_elems += elem_explicit(0x0002, 0x0002, 'UI', pad_even(b'1.2.840.10008.5.1.4.1.1.1.1', b'\x00'))  # SOP Class UID (IntraOral X-Ray)
meta_elems += elem_explicit(0x0002, 0x0003, 'UI', pad_even(b'1.2.3.4.5.6.7.8.9.0', b'\x00'))  # SOP Instance UID
meta_elems += elem_explicit(0x0002, 0x0010, 'UI', transfer_syntax)

meta_group_length = elem_explicit(0x0002, 0x0000, 'UL', struct.pack('<I', len(meta_elems)))

# --- Main dataset (Implicit VR Little Endian) ---
width, height = 64, 64
pixels = bytearray(width * height)
for y in range(height):
    for x in range(width):
        pixels[y * width + x] = (x * 4 + y * 2) % 256
pixel_data = bytes(pixels)

dataset = b''
dataset += elem_implicit(0x0028, 0x0002, us(1))                                   # SamplesPerPixel
dataset += elem_implicit(0x0028, 0x0004, pad_even(b'MONOCHROME2'))                 # PhotometricInterpretation
dataset += elem_implicit(0x0028, 0x0010, us(height))                               # Rows
dataset += elem_implicit(0x0028, 0x0011, us(width))                                # Columns
dataset += elem_implicit(0x0028, 0x0100, us(8))                                    # BitsAllocated
dataset += elem_implicit(0x0028, 0x0101, us(8))                                    # BitsStored
dataset += elem_implicit(0x0028, 0x0102, us(7))                                    # HighBit
dataset += elem_implicit(0x0028, 0x0103, us(0))                                    # PixelRepresentation
dataset += elem_implicit(0x7FE0, 0x0010, pixel_data)                               # PixelData

with open(r'C:\Users\arayi\Desktop\Stom\test\fixtures\sample_uncompressed.dcm', 'wb') as f:
    f.write(b'\x00' * 128)
    f.write(b'DICM')
    f.write(meta_group_length)
    f.write(meta_elems)
    f.write(dataset)

print("wrote sample_uncompressed.dcm,", 128 + 4 + len(meta_group_length) + len(meta_elems) + len(dataset), "bytes")
