#!/usr/bin/env python3
"""Deterministic Xcode project generator. The generated project is checked in.
End users do NOT need to run this script or install XcodeGen/CocoaPods.
"""
from pathlib import Path
import hashlib, json, plistlib
from xml.sax.saxutils import escape
ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'LightPlan.xcodeproj'
objects = {}
def uid(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def obj(identity, isa, **fields):
    key = uid(identity); objects[key] = {'isa':isa, **fields}; return key
def ref(path, kind=None, name=None):
    extension=Path(path).suffix
    kind=kind or {'.swift':'sourcecode.swift','.xcstrings':'text.json.xcstrings','.xcassets':'folder.assetcatalog','.plist':'text.plist.xml','.xcprivacy':'text.xml','.xcconfig':'text.xcconfig','.storekit':'text','.strings':'text.plist.strings'}.get(extension,'text')
    return obj('file:'+path,'PBXFileReference',lastKnownFileType=kind,path=path,sourceTree='SOURCE_ROOT',**({'name':name} if name else {}))
def build(name, file=None, product=None, **extra):
    return obj('build:'+name,'PBXBuildFile',**({'fileRef':file} if file else {'productRef':product}),**extra)
def configs(name, base, debug=None, release=None):
    rows=[]
    for mode, additions in [('Debug',debug or {}),('Release',release or {})]:
        fields={'buildSettings': {**base,**additions},'name':mode}
        if name=='project': fields['baseConfigurationReference']=config_ref
        rows.append(obj('config:'+name+mode,'XCBuildConfiguration',**fields))
    return obj('configs:'+name,'XCConfigurationList',buildConfigurations=rows,defaultConfigurationIsVisible='0',defaultConfigurationName='Release')
def sources(target, paths):
    return obj('sources:'+target,'PBXSourcesBuildPhase',buildActionMask='2147483647',files=[build(target+':'+p,ref(p)) for p in paths],runOnlyForDeploymentPostprocessing='0')
def resources(target, paths):
    return obj('resources:'+target,'PBXResourcesBuildPhase',buildActionMask='2147483647',files=[build(target+':resource:'+p,ref(p)) for p in paths],runOnlyForDeploymentPostprocessing='0')
def plist(path, value):
    destination=ROOT/path; destination.parent.mkdir(parents=True,exist_ok=True); destination.write_bytes(plistlib.dumps(value,sort_keys=False))

def info(identifier, name, extension=False):
    value={'CFBundleDevelopmentRegion':'$(DEVELOPMENT_LANGUAGE)','CFBundleExecutable':'$(EXECUTABLE_NAME)','CFBundleIdentifier':identifier,'CFBundleInfoDictionaryVersion':'6.0','CFBundleName':'$(PRODUCT_NAME)','CFBundleDisplayName':name,'CFBundlePackageType':'XPC!' if extension else 'APPL','CFBundleShortVersionString':'$(MARKETING_VERSION)','CFBundleVersion':'$(CURRENT_PROJECT_VERSION)','AppGroupIdentifier':'$(APP_GROUP_ID)','LifetimeProductIdentifier':'$(LIFETIME_PRODUCT_ID)','ITSAppUsesNonExemptEncryption':False}
    if extension: value['NSExtension']={'NSExtensionPointIdentifier':'com.apple.widgetkit-extension'}
    else:
        value.update({'LSRequiresIPhoneOS':True,'NSLocationWhenInUseUsageDescription':'Show sunlight directions at a place you choose. You can also enter coordinates without sharing your location.','UILaunchScreen':{},'UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight'],'UISupportedInterfaceOrientations~ipad':['UIInterfaceOrientationPortrait','UIInterfaceOrientationPortraitUpsideDown','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight'],'CFBundleURLTypes':[{'CFBundleURLName':'LightPlan','CFBundleURLSchemes':['lightplan']}]})
    return value

(ROOT/'ios/Config').mkdir(parents=True,exist_ok=True)
(ROOT/'ios/Config/Project.xcconfig').write_text('''// One source for signing identifiers. Team can be selected in Xcode.
APP_BUNDLE_ID = com.arenovo.lightplan
APP_GROUP_ID = group.com.arenovo.lightplan
LIFETIME_PRODUCT_ID = com.arenovo.lightplan.lifetime
#include? "Local.xcconfig"
''')
(ROOT/'ios/Config/Local.xcconfig.example').write_text('''// Optional local overrides, never commit the real Local.xcconfig.
DEVELOPMENT_TEAM = YOUR_TEAM_ID
// Change all related identifiers together when using a different registered App ID.
// APP_BUNDLE_ID = com.yourcompany.lightplan
// APP_GROUP_ID = group.com.yourcompany.lightplan
// LIFETIME_PRODUCT_ID = com.yourcompany.lightplan.lifetime
''')
config_ref=ref('ios/Config/Project.xcconfig')
for target in ['LightPlan','LightPlanWidget']:
    plist(f'ios/{target}/Info.plist',info('$(PRODUCT_BUNDLE_IDENTIFIER)','LightPlan',target.endswith('Widget')))
    plist(f'ios/{target}/{target}.entitlements',{'com.apple.security.application-groups':['$(APP_GROUP_ID)']})
package=obj('package:core','XCLocalSwiftPackageReference',relativePath='packages/LightPlanCore')
app_product=obj('product:app','PBXFileReference',explicitFileType='wrapper.application',includeInIndex='0',path='LightPlan.app',sourceTree='BUILT_PRODUCTS_DIR')
widget_product=obj('product:widget','PBXFileReference',explicitFileType='wrapper.app-extension',includeInIndex='0',path='LightPlanWidget.appex',sourceTree='BUILT_PRODUCTS_DIR')
test_product=obj('product:uitests','PBXFileReference',explicitFileType='wrapper.cfbundle',includeInIndex='0',path='LightPlanUITests.xctest',sourceTree='BUILT_PRODUCTS_DIR')

targets=[]
base_target={'SWIFT_VERSION':'6.0','SWIFT_STRICT_CONCURRENCY':'complete','SWIFT_EMIT_LOC_STRINGS':'YES','IPHONEOS_DEPLOYMENT_TARGET':'17.0','TARGETED_DEVICE_FAMILY':'1,2','CODE_SIGN_STYLE':'Automatic','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','SUPPORTS_MACCATALYST':'NO','SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD':'NO','PRODUCT_NAME':'$(TARGET_NAME)','SDKROOT':'iphoneos'}
for target,folder,product,is_widget in [('LightPlan','ios/LightPlan',app_product,False),('LightPlanWidget','ios/LightPlanWidget',widget_product,True)]:
    paths=[str(p.relative_to(ROOT)) for p in sorted((ROOT/folder).rglob('*.swift'))]+['ios/Shared/L10n.swift']
    product_dep=obj('package-product:'+target,'XCSwiftPackageProductDependency',package=package,productName='LightPlanCore')
    frameworks=obj('frameworks:'+target,'PBXFrameworksBuildPhase',buildActionMask='2147483647',files=[build(target+':core',product=product_dep)],runOnlyForDeploymentPostprocessing='0')
    resource_paths=['ios/Shared/Localizable.xcstrings',folder+'/PrivacyInfo.xcprivacy']
    if not is_widget: resource_paths += ['ios/LightPlan/Assets.xcassets']
    res=resources(target,resource_paths)
    if not is_widget:
        children=[]
        for p in sorted((ROOT/folder).glob('*.lproj/InfoPlist.strings')):
            path=str(p.relative_to(ROOT)); children.append(ref(path,kind='text.plist.strings',name=p.parent.stem))
        variant=obj('localized:InfoPlist','PBXVariantGroup',children=children,name='InfoPlist.strings',sourceTree='<group>')
        objects[res]['files'].append(build('InfoPlist-localizations',variant))
    phases=[sources(target,paths),frameworks,res]
    deps=[]
    if not is_widget:
        embed=obj('embed:widget','PBXCopyFilesBuildPhase',buildActionMask='2147483647',dstPath='',dstSubfolderSpec='13',files=[build('embed-widget',widget_product,settings={'ATTRIBUTES':['RemoveHeadersOnCopy']})],name='Embed App Extensions',runOnlyForDeploymentPostprocessing='0')
        phases.append(embed)
        proxy=obj('proxy:widget','PBXContainerItemProxy',containerPortal=uid('project'),proxyType='1',remoteGlobalIDString=uid('target:LightPlanWidget'),remoteInfo='LightPlanWidget')
        deps.append(obj('dependency:widget','PBXTargetDependency',target=uid('target:LightPlanWidget'),targetProxy=proxy))
    settings={**base_target,'PRODUCT_BUNDLE_IDENTIFIER':'$(APP_BUNDLE_ID).widget' if is_widget else '$(APP_BUNDLE_ID)','INFOPLIST_FILE':folder+'/Info.plist','CODE_SIGN_ENTITLEMENTS':folder+'/'+target+'.entitlements','GENERATE_INFOPLIST_FILE':'NO','SKIP_INSTALL':'YES' if is_widget else 'NO'}
    if is_widget: settings['APPLICATION_EXTENSION_API_ONLY']='YES'
    else: settings['ASSETCATALOG_COMPILER_APPICON_NAME']='AppIcon'
    target_ref=obj('target:'+target,'PBXNativeTarget',buildConfigurationList=configs(target,settings),buildPhases=phases,buildRules=[],dependencies=deps,name=target,packageProductDependencies=[product_dep],productName=target,productReference=product,productType='com.apple.product-type.app-extension' if is_widget else 'com.apple.product-type.application')
    targets.append(target_ref)
uitest_sources=[str(p.relative_to(ROOT)) for p in sorted((ROOT/'ios/LightPlanVisualUITests').glob('*.swift'))]
testframework=obj('frameworks:tests','PBXFrameworksBuildPhase',buildActionMask='2147483647',files=[],runOnlyForDeploymentPostprocessing='0')
proxy=obj('proxy:app','PBXContainerItemProxy',containerPortal=uid('project'),proxyType='1',remoteGlobalIDString=uid('target:LightPlan'),remoteInfo='LightPlan')
testdep=obj('dependency:app','PBXTargetDependency',target=uid('target:LightPlan'),targetProxy=proxy)
testsettings={**base_target,'PRODUCT_BUNDLE_IDENTIFIER':'$(APP_BUNDLE_ID).uitests','GENERATE_INFOPLIST_FILE':'YES','TEST_TARGET_NAME':'LightPlan'}
targets.append(obj('target:LightPlanUITests','PBXNativeTarget',buildConfigurationList=configs('tests',testsettings),buildPhases=[sources('tests',uitest_sources),testframework,resources('tests',['ios/StoreKit/LightPlan.storekit'])],buildRules=[],dependencies=[testdep],name='LightPlanUITests',productName='LightPlanUITests',productReference=test_product,productType='com.apple.product-type.bundle.ui-testing'))
project_configs=configs('project',{'ALWAYS_SEARCH_USER_PATHS':'NO','CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES','CLANG_WARN_DOCUMENTATION_COMMENTS':'YES','GCC_C_LANGUAGE_STANDARD':'gnu17','CLANG_CXX_LANGUAGE_STANDARD':'gnu++20','ENABLE_STRICT_OBJC_MSGSEND':'YES','ENABLE_USER_SCRIPT_SANDBOXING':'YES','MARKETING_VERSION':'1.0.0','CURRENT_PROJECT_VERSION':'1','SWIFT_VERSION':'6.0','SWIFT_STRICT_CONCURRENCY':'complete','IPHONEOS_DEPLOYMENT_TARGET':'17.0','SDKROOT':'iphoneos'},debug={'DEBUG_INFORMATION_FORMAT':'dwarf','ENABLE_TESTABILITY':'YES','GCC_OPTIMIZATION_LEVEL':'0','ONLY_ACTIVE_ARCH':'YES','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG $(inherited)','SWIFT_OPTIMIZATION_LEVEL':'-Onone'},release={'DEBUG_INFORMATION_FORMAT':'dwarf-with-dsym','SWIFT_COMPILATION_MODE':'wholemodule','SWIFT_OPTIMIZATION_LEVEL':'-O','VALIDATE_PRODUCT':'YES'})
products=obj('group:products','PBXGroup',children=[app_product,widget_product,test_product],name='Products',sourceTree='<group>')
variant_children = {child for value in objects.values() if value['isa']=='PBXVariantGroup' for child in value['children']}
files=[key for key,value in objects.items() if value['isa'] in ['PBXFileReference','PBXVariantGroup'] and key not in variant_children and key not in [app_product,widget_product,test_product]]
main_group=obj('group:main','PBXGroup',children=files+[products],sourceTree='<group>')
project=obj('project','PBXProject',attributes={'BuildIndependentTargetsInParallel':'YES','LastUpgradeCheck':'2600','TargetAttributes':{uid('target:LightPlan'):{'CreatedOnToolsVersion':'26.0','SystemCapabilities':{'com.apple.ApplicationGroups.iOS':{'enabled':'1'}}},uid('target:LightPlanWidget'):{'CreatedOnToolsVersion':'26.0','SystemCapabilities':{'com.apple.ApplicationGroups.iOS':{'enabled':'1'}}},uid('target:LightPlanUITests'):{'CreatedOnToolsVersion':'26.0','TestTargetID':uid('target:LightPlan')}}},buildConfigurationList=project_configs,compatibilityVersion='Xcode 14.0',developmentRegion='en',hasScannedForEncodings='0',knownRegions=['en','zh-Hans','zh-Hant','ja','ko','de','fr','th','pt-PT','Base'],mainGroup=main_group,packageReferences=[package],productRefGroup=products,projectDirPath='',projectRoot='',targets=targets)

def serialize(value,depth=0):
    indent='\t'*depth
    if isinstance(value,dict): return '{\n'+''.join('\t'*(depth+1)+json.dumps(str(k))+ ' = '+serialize(v,depth+1)+';\n' for k,v in value.items())+indent+'}'
    if isinstance(value,list): return '(\n'+''.join('\t'*(depth+1)+serialize(v,depth+1)+',\n' for v in value)+indent+')'
    return json.dumps(str(value),ensure_ascii=False)
PROJECT.mkdir(exist_ok=True)
(PROJECT/'project.pbxproj').write_text('// !$*UTF8*$!\n'+serialize({'archiveVersion':'1','classes':{},'objectVersion':'56','objects':objects,'rootObject':project})+'\n')
shared=PROJECT/'xcshareddata/xcschemes'; shared.mkdir(parents=True,exist_ok=True)
def reference(target,product): return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid("target:"+target)}" BuildableName="{product}" BlueprintName="{target}" ReferencedContainer="container:LightPlan.xcodeproj"/>'
appref=reference('LightPlan','LightPlan.app');testref=reference('LightPlanUITests','LightPlanUITests.xctest')
scheme=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.7">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{appref}</BuildActionEntry></BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{testref}</TestableReference></Testables></TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{appref}</BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{appref}</BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
(shared/'LightPlan.xcscheme').write_text(scheme)
(PROJECT/'project.xcworkspace').mkdir(exist_ok=True)
(PROJECT/'project.xcworkspace/contents.xcworkspacedata').write_text('<?xml version="1.0" encoding="UTF-8"?><Workspace version="1.0"><FileRef location="self:"/></Workspace>\n')
print(f'Wrote {PROJECT}; {len(objects)} project objects, {len(targets)} targets.')
