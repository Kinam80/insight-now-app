@echo off
echo [깃허브 업로드 시작]
git add .
git commit -m "UI 수정 및 업데이트"
git push
echo [업로드 완료! 이제 Render에서 확인하세요.]
pause