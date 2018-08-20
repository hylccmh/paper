#!/bin/sh

#  WallPaperScript.sh

#计时
SECONDS=0

#取当前时间字符串添加到文件结尾
now=$(date +"%Y%m%d-%H:%M")

# 获取 setting.plist 文件路径
setting_path=./setting.plist

# 项目名称
project_name=$(/usr/libexec/PlistBuddy -c "print project_name" ${setting_path})

# 项目路径
project_path=$(/usr/libexec/PlistBuddy -c "print project_path" ${setting_path})

# workspace/xcodeproj 路径(根据项目是否使用cocoapod,确定打包的方式)
if [ -d "./${project_name}.xcworkspace" ];then # 项目中存在workspace
workspace_path="${project_path}/${project_name}.xcworkspace"
else # 项目中不存在 workspace
workspace_path="${project_path}/${project_name}.xcodeproj"
fi

# scheme名称
scheme_name=$(/usr/libexec/PlistBuddy -c "print scheme_name" ${setting_path})

# 项目版本
project_version=$(/usr/libexec/PlistBuddy -c "print project_version" ${setting_path})

# 开发者账号
dev_account=$(/usr/libexec/PlistBuddy -c "print dev_account" ${setting_path})

# 开发者密码
dev_password=$(/usr/libexec/PlistBuddy -c "print dev_password" ${setting_path})

# 配置打包样式：Release/ad-hoc/Debug
configuration=$(/usr/libexec/PlistBuddy -c "print configuration" ${setting_path})

# 发布地址：蒲公英->PGY，苹果->APPStore, fir.im->FI
upload_address=$(/usr/libexec/PlistBuddy -c "print upload_address" ${setting_path})

# ipa包名称：项目名+版本号+打包类型
ipa_name=$(/usr/libexec/PlistBuddy -c "print ipa_name" ${setting_path})

# ipa包路径
ipa_path2=$(/usr/libexec/PlistBuddy -c "print ipa_path" ${setting_path})/${now}
ipa_path="${ipa_path2}-V${project_version}-${upload_address}"

# 打包配置plist文件路径 (初始化)
plist_path=$(/usr/libexec/PlistBuddy -c "print plist_path" ${setting_path})

# 编译build路径
archive_path="${ipa_path}/${project_name}.xcarchive"

# 上传到蒲公英设置
user_key=$(/usr/libexec/PlistBuddy -c "print user_key" ${setting_path})
api_key=$(/usr/libexec/PlistBuddy -c "print api_key" ${setting_path})
password=$(/usr/libexec/PlistBuddy -c "print password" ${setting_path})

# 上传fir.im 设置
fir_token=$(/usr/libexec/PlistBuddy -c "print fir_token" ${setting_path})

#打包方式配置，以及相应的需求配置
if [ ${upload_address} == "APPStore" ];then # 发布到 AppStore 配置 Release
    configuration="Release"
    plist_path=${project_path}/exportAppstore.plist
elif [ ${upload_address} == "PGY" ] ||[ ${upload_address} == "FI" ];then # 发布到第三方平台可 配置 Release、Debug
    if [ ${configuration} == "Release" ];then
     plist_path=${project_path}/exportAdHoc.plist
    else
     plist_path=${project_path}/exportDevelopment.plist
    fi
else # 只打包，不发布到任何平台
    if [ ${configuration} == "Release" ];then
       plist_path=${project_path}/exportAppstore.plist
    else
       plist_path=${project_path}/exportDevelopment.plist
    fi
fi

echo '=============正在清理工程============='
xcodebuild clean -configuration ${configuration} -quiet || exit

echo '清理完成-->>>--正在编译工程:'${configuration}

# 通过workspace方式打包
if [ -d "./${project_name}.xcworkspace" ];then # 项目中存在workspace
    xcodebuild archive -workspace ${workspace_path} -scheme ${scheme_name} \
    -configuration ${configuration} \
    -archivePath ${archive_path} -quiet || exit
else #通过xcodeproj 方式打包
    xcodebuild archive -project ${workspace_path} -scheme ${scheme_name} \
    -configuration ${configuration} \
    -archivePath ${archive_path} -quiet || exit
fi

# 检查是否构建成功(build)
if [ -d "$archive_path" ] ; then
    echo '=============项目构建成功============='
else
    echo '=============项目构建失败============='
    exit 1
fi

echo '编译完成-->>>--开始ipa打包'
xcodebuild -exportArchive -archivePath ${archive_path} \
-configuration ${configuration} \
-exportPath ${ipa_path} \
-exportOptionsPlist ${plist_path} \
-quiet || exit

if [ -e ${ipa_path}/${ipa_name}.ipa ]; then
    echo '=============ipa包导出成功============='
    open $ipa_path
else
    echo '=============ipa包导出失败============'
fi

echo '打包ipa完成-->>>--开始发布ipa包'

if [ ${upload_address} == "APPStore" ];then # 发布到APPStore
    echo '发布ipa包到 =============APPStore============='
    altoolPath="/Applications/Xcode.app/Contents/Applications/Application Loader.app/Contents/Frameworks/ITunesSoftwareService.framework/Versions/A/Support/altool"
    "$altoolPath" --validate-app -f ${ipa_path}/${ipa_name}.ipa -u ${dev_account} -p ${dev_password} -t ios --output-format xml
    "$altoolPath" --upload-app -f ${ipa_path}/${ipa_name}.ipa -u ${dev_account} -p ${dev_password} -t ios --output-format xml

    if [ $? = 0 ];then
    echo "=============提交AppStore成功 ============="
    else
    echo "=============提交AppStore失败 ============="
    fi

elif [ ${upload_address} == "PGY" ];then # 发布到蒲公英平台
    echo '发布ipa包到 =============蒲公英平台============='
    curl -F "file=@${ipa_path}/${ipa_name}.ipa" -F "uKey=${user_key}" -F "_api_key=${api_key}" -F "password=${password}" https://www.pgyer.com/apiv1/app/upload

    if [ $? = 0 ];then
    echo "=============提交蒲公英成功 ============="
    else
    echo "=============提交蒲公英失败 ============="
    fi

elif [ ${upload_address} == "FI" ];then # 发布到fir.im 平台
    echo '发布ipa包到 =============fir.im平台============'
    # 需要先在本地安装 fir 插件,安装fir插件命令: gem install fir-cli
    fir login -T ${fir_token}              # fir.im token
    fir publish  ${ipa_path}/${ipa_name}.ipa

    if [ $? = 0 ];then
    echo "=============提交fir.im成功 ============="
    else
    echo "=============提交fir.im失败 ============="
    fi
else # 未配置发布地址
    echo "=============未发布 ipa包(打包方式:$configuration) 到任何平台============="
fi

# 输出总用时
echo "执行耗时: ${SECONDS}秒"

exit 0


















