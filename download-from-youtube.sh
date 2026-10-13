#!/bin/bash

usage() {
    cat <<EOF
Использование:
  $0 [-q КАЧЕСТВО] [-i ID_ФОРМАТА] [-f ФАЙЛ] [ССЫЛКА]

Параметры:
  -q КАЧЕСТВО   максимальная высота видео: 360, 480, 720, 1080, 1440, 2160
                или best / worst
  -i ID         точный ID формата видео (из yt-dlp -F), вместо -q
  -f ФАЙЛ       файл со списком ссылок (по одной на строку, # - комментарий)
  -u            установить/обновить yt-dlp до последней версии с GitHub
  -h            показать эту справку

Примеры:
  $0 -u                   (только обновить yt-dlp)
  $0 -u -q 1080 URL       (обновить и сразу скачать)
  $0 -q 1080 https://youtu.be/XXXX
  $0 -q 720 -f list.txt
  $0 -i 137 https://youtu.be/XXXX
  $0                      (интерактивный режим)
EOF
}

# Установка/обновление yt-dlp (бинарник с GitHub вместо версии из apt)
update_ytdlp() {
    echo "Обновление yt-dlp..."
    sudo apt remove -y yt-dlp
    sudo curl -fL https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp \
         -o /usr/local/bin/yt-dlp || { echo "Не удалось скачать yt-dlp."; return 1; }
    sudo chmod a+rx /usr/local/bin/yt-dlp
    hash -r
    echo "Установлена версия: $(yt-dlp --version)"
}

QUALITY=""
VIDEO_ID=""
LIST_FILE=""
DO_UPDATE=0

while getopts "q:i:f:uh" opt; do
    case $opt in
        q) QUALITY="$OPTARG" ;;
        i) VIDEO_ID="$OPTARG" ;;
        f) LIST_FILE="$OPTARG" ;;
        u) DO_UPDATE=1 ;;
        h) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

URL=$1

# Обновление по запросу (-u)
if [ "$DO_UPDATE" -eq 1 ]; then
    update_ytdlp || exit 1
    # Если больше ничего не задано - просто выходим
    if [ -z "$URL" ] && [ -z "$LIST_FILE" ]; then
        exit 0
    fi
fi

# Проверяем установлен ли yt-dlp
if ! command -v yt-dlp &> /dev/null; then
    echo "yt-dlp не установлен."
    read -p "Установить последнюю версию с GitHub? [Y/n]: " ANSWER
    case "${ANSWER:-y}" in
        [Yy]*|[Дд]*) update_ytdlp || exit 1 ;;
        *) exit 1 ;;
    esac
fi

# Собираем список ссылок
URLS=()
if [ -n "$LIST_FILE" ]; then
    if [ ! -f "$LIST_FILE" ]; then
        echo "Файл не найден: $LIST_FILE"
        exit 1
    fi
    while IFS= read -r line || [ -n "$line" ]; do
        line=$(echo "$line" | tr -d '\r' | xargs)
        [ -z "$line" ] && continue
        [[ "$line" == \#* ]] && continue
        URLS+=("$line")
    done < "$LIST_FILE"
fi

if [ -n "$URL" ]; then
    URLS+=("$URL")
fi

if [ ${#URLS[@]} -eq 0 ]; then
    read -p "Введите ссылку на YouTube видео: " URL
    [ -z "$URL" ] && { echo "Ссылка не указана."; exit 1; }
    URLS+=("$URL")
fi

# Если качество не задано - спрашиваем
if [ -z "$QUALITY" ] && [ -z "$VIDEO_ID" ]; then
    if [ ${#URLS[@]} -eq 1 ]; then
        echo ""
        echo "Доступные форматы:"
        yt-dlp -F "${URLS[0]}"
        echo ""
        read -p "Введите ID формата (например 137) или Enter для лучшего качества: " VIDEO_ID
    else
        read -p "Введите качество (360/480/720/1080/1440/2160/best) [best]: " QUALITY
    fi
fi

# Строим селектор формата
if [ -n "$VIDEO_ID" ]; then
    FORMAT="${VIDEO_ID}+bestaudio/best"
else
    case "${QUALITY:-best}" in
        best)  FORMAT="bestvideo+bestaudio/best" ;;
        worst) FORMAT="worstvideo+worstaudio/worst" ;;
        *[!0-9]*)
            echo "Неверное качество: $QUALITY"
            exit 1 ;;
        *)     FORMAT="bestvideo[height<=${QUALITY}]+bestaudio/best[height<=${QUALITY}]" ;;
    esac
fi

# Скачивание
TOTAL=${#URLS[@]}
FAILED=()
N=0

# Общий прогрессбар: [██████░░░░░░░░░░░░░░]  30% (3/10)
overall_bar() {
    local done=$1 total=$2 width=30
    local filled=$(( done * width / total ))
    local percent=$(( done * 100 / total ))
    local bar="" i
    for ((i = 0; i < width; i++)); do
        if [ $i -lt $filled ]; then bar+="█"; else bar+="░"; fi
    done
    printf "Общий прогресс: [%s] %3d%% (%d/%d)\n" "$bar" "$percent" "$done" "$total"
}

for u in "${URLS[@]}"; do
    N=$((N + 1))
    echo ""
    echo "=== Видео $N из $TOTAL: $u"
    # --progress: показывать полосу загрузки (скорость, размер, ETA) для каждого файла
    if ! yt-dlp -f "$FORMAT" --merge-output-format mp4 --progress "$u"; then
        FAILED+=("$u")
    fi
    overall_bar "$N" "$TOTAL"
done

echo ""
echo "Загрузка завершена! Успешно: $((TOTAL - ${#FAILED[@]})) из $TOTAL"
if [ ${#FAILED[@]} -gt 0 ]; then
    echo "Не удалось скачать:"
    printf '  %s\n' "${FAILED[@]}"
    exit 1
fi
