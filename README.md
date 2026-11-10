# CKA 8 tuần

Trang ôn thi Certified Kubernetes Administrator: lộ trình 8 tuần, 44 bài học, 135 bài tập, 35 bài lab, flashcard, thi thử 2 giờ.

Trang tĩnh một file (`index.html`), deploy trên Vercel không cần build.

## Sửa nội dung

- Bài học: `src/lessons/w1.md` … `w8.md` (mỗi bài bắt đầu bằng `# L: Tên bài`, bài tập nằm giữa `:::ex` / `:::sol` / `:::end`).
- Giao diện, lab, flashcard: `src/template.html`.
- Build lại `index.html`: `pip install markdown && python3 src/build.py` (chạy ở thư mục gốc).

## Phòng thi + terminal VM

Tab **⌨ Phòng thi**: đề bên trái, terminal của VM bên phải (giống giao diện thi thật). Terminal là [ttyd](https://github.com/tsl0922/ttyd) chạy trên VM lab, nhúng bằng iframe.

```bash
ssh namhv25@192.168.64.5
curl -fsSL https://<ten-site>.vercel.app/scripts/setup-web-terminal.sh | bash
# có mật khẩu: TTYD_PASS='...' bash setup-web-terminal.sh
```
Mở `https://192.168.64.5:7681` một lần để chấp nhận chứng chỉ tự ký, rồi bấm **Kết nối** trong trang.
