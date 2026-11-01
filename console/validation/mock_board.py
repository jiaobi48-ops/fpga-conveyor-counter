import struct
import numpy as np
from protocol import *
class FakeTransport:

    def __init__(self):
        self.h = [0] * 128
        self.h[0] = MAGIC
        self.h[1] = 3
        self.h[31] = 1
        self.h[CFG:CFG + 10] = [416, 376, 4, 96, 128, 144, 52, 25, 32, 13]
        self.h[PAGES + 1] = 7181
        self.h[PAGES + 3] = 1
        self.h[PAGES + 4] = 1
        self.h[PAGES + 14] = 12780545
        self.gray_id = 0
        self.gray_phase = 0
        self.gray_stopped = False
        self.respond = True
        self.full = None
        self.gray_data = bytes((i * 4 & 255 for i in range(14400)))
        self.corrupt = False
        self.closed = False

    def connect(self):
        pass

    def close(self):
        self.closed = True

    def read(self, a, n):
        if a == BASE:
            return struct.pack('<128I', *self.h)
        if a == GRAY:
            if not self.gray_phase:
                if not self.gray_stopped:
                    self.gray_id += 1
                h = [0] * 16
                h[:7] = [1179601969, self.gray_id, 160, 90, 14400, fnv(self.gray_data), 12780545]
                h[8] = 100
                h[10] = MAGIC
                self.gh = struct.pack('<16I', *h)
                self.gray_phase = 1
            else:
                self.gray_phase = 0
            return self.gh
        if a == GRAY + 64:
            return self.gray_data
        if a == PIXELS - 64 and n == N + 128:
            if self.corrupt:
                return self.full[:-1] + b'\x00'
            return self.full
        raise AssertionError(('unexpected read', hex(a), n))

    def write(self, a, values):
        assert BASE + 8 <= a and a + len(values) * 4 <= BASE + 44
        i = (a - BASE) // 4
        self.h[i:i + len(values)] = values
        if i != 2 or not self.respond:
            return
        t = self.h[2]
        seal = SEAL
        for v in self.h[2:10]:
            seal ^= v
        self.h[STATE] = 2
        self.h[ERR] = 0
        if seal != self.h[10]:
            self.h[STATE] = 3
            self.h[ERR] = 1
        elif self.h[3] == 2:
            if self.h[4] != self.h[SEQ]:
                self.h[STATE] = 3
                self.h[ERR] = 2
            else:
                g = self.h[5:10]
                assert valid_roi(g)
                self.h[CFG:CFG + 5] = g
                area = g[2] * (g[4] - g[3])
                self.h[CFG + 6:CFG + 9] = [(area * 52 + 127) // 128, area * 25 // 128, (area * 32 + 127) // 128]
                self.h[PAGES + 3] += 1
        elif self.h[3] == 1:
            self.h[SEQ] += 1
            s = self.h[SEQ]
            a = np.zeros((720, 1280, 3), dtype=np.uint8)
            a[:, :, 0] = 40
            a[:, :, 1] = 80
            a[:, :, 2] = 160
            a[200, 400, 0] = s % 30 * 8
            raw = a.tobytes()
            self.full = b'Z' * 64 + raw + b'Z' * 64
            self.h[36:40] = [1280, 720, 3840, N]
            self.h[40:51] = [fnv(raw), 0, 16777216, 1, 2, 1, 1, 32, 100, 1, PIXELS]
            self.h[96] = s + 100
        elif self.h[3] in (4,5,6,7):
            op=self.h[3];value=self.h[5]
            if op==4:self.h[73]=(self.h[73]&~12)|value
            if op==5:self.h[69]=value
            if op==6:self.h[73]=(self.h[73]&~2)|(value<<1)
            if op==7:self.h[84]+=1;self.h[80]=0
            else:self.h[83]+=1
            bits=self.h[73]&12
            self.h[81]=13|((bits&4)<<8)|((bits&8)<<8)|(4096 if bits==12 else 0)
        self.h[ACK] = t
