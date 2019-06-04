using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;
using System.Web.UI;
using System.Web.UI.WebControls;

using EW.Azure.Utilities;

namespace SampleIisWebApp
{
    public partial class SiteMaster : MasterPage
    {
 
        protected static string AssemblyBuildVersion {
            get
            {
                return System.Reflection.Assembly.GetExecutingAssembly().GetName().Version.ToString();
            }

        }

        protected static string AvailabilityZone {
            get
            {
                return IMDSUtility.JsonQuery("/instance/compute/zone");
            }
        }

        protected void Page_Load(object sender, EventArgs e)
        {
 
        }
    }
}