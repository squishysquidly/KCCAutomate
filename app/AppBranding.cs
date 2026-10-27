using System;
using System.Linq;
using System.Reflection;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace KCCAutomate {
    public static class AppBranding {
        static readonly Lazy<ImageSource> icon=new Lazy<ImageSource>(delegate {
            using(var stream=Assembly.GetExecutingAssembly().GetManifestResourceStream("KCCAutomate.Icon.ico")){
                if(stream==null)throw new InvalidOperationException("The application icon is missing from this build.");
                var decoder=new IconBitmapDecoder(stream,BitmapCreateOptions.PreservePixelFormat,BitmapCacheOption.OnLoad);
                var image=decoder.Frames.OrderByDescending(frame=>frame.PixelWidth).First();image.Freeze();return image;
            }
        });
        public static ImageSource Icon {get{return icon.Value;}}
    }
}
