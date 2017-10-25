
# -----color list-----

declare -r BK_CODE_PRE="\033["
declare -r BK_CODE_RESET="${BK_CODE_PRE}0m"
# style
declare -r BK_CODE_BOLD="${BK_CODE_PRE}1m"
declare -r BK_CODE_UNDERLINE="${BK_CODE_PRE}4m"
# color
declare -r BK_CODE_RED="${BK_CODE_PRE}31m"
declare -r BK_CODE_GREEN="${BK_CODE_PRE}32m"
declare -r BK_CODE_YELLOW="${BK_CODE_PRE}33m"
declare -r BK_CODE_BLUE="${BK_CODE_PRE}34m"

# -----lib functions-----

# ---for systemd---

function set_serv()
{
    if [[ $# > 0 ]]; then
        systemctl enable $@
        systemctl restart $@
    fi
}

function show_serv()
{
    if [[ $# > 0 ]]; then
        systemctl status $@
    fi
}

function go_serv()
{
    if [[ -n "$1" ]]; then
        set_serv "$1.service"
        show_serv "$1.service"
    fi
}

# ---for configuration---

# get_key "Port 22"
function get_key()
{
    if [[ -n "$1" ]]; then
        echo $(expr "$1" : "\(\w*\)")
    fi
}

# make_re "...0..." "0" "Port 22"
function make_re()
{
    if [[ $# = 3 ]]; then
        declare re="$1"; declare tpl="$2"; declare src="$3"
        declare key=$(get_key $src)
        echo "$re" | sed "s/$tpl/$key/g"
    fi
}

# set_value "...0..." "0" "Port 22" "/etc/ssh/sshd.conf"
function set_value()
{
    if [[ $# = 4 ]]; then
        declare re=$(make_re "$1" "$2" "$3")
        declare new="$3"; declare file="$4"
        declare lines=$(sed -rn "/^$re$/=" "$file"); echo $lines

        echo -e "${BK_CODE_YELLOW}${BK_CODE_BOLD}set $re to $new in $file${BK_CODE_RESET}"

        declare -i i=0; declare cmd
        for l in $lines; do
            ((i++))
            if [[ $i = 1 ]]; then
                cmd="$l c $new"
            else
                cmd="$l d; $cmd"
            fi
        done
        if [[ $i > 0 ]]; then
            echo "sed command: $cmd"
            sed -i.bak "$cmd" "$file"
        else # i=0
            declare lines=$(sed -rn "/^#$re$/=" "$file")
            for l in $lines; do
                ((i++))
                sed -i.bak "$l a $new" "$file"
                break
            done
            if [[ $i = 0 ]]; then
                sed -i.bak "$ a $new" "$file"
            fi
        fi
        grep --color=auto "$re" "$file"
    fi
}
