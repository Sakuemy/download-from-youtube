#!/bin/bash

# Проверяем установлен ли yt-dlp
if ! command -v yt-dlp &> /dev/null
then
    echo "yt-dlp не установлен. Установите его:"
    echo "sudo apt install yt-dlp"
    exit 1
fi

# Запрос ссылки
URL=$1

if [ -z "$URL" ]; then
    read -p "Введите ссылку на YouTube видео: " URL
fi

# Показываем доступные форматы
echo ""
echo "Доступные форматы:"
yt-dlp -F "$URL"

echo ""
read -p "Введите ID видео формата (например 137) для нужного качества: " VIDEO_ID

# Скачивание видео + лучший аудио поток
yt-dlp -f "${VIDEO_ID}+bestaudio" \
       --merge-output-format mp4 \
       "$URL"

echo ""
echo "Загрузка завершена!"
