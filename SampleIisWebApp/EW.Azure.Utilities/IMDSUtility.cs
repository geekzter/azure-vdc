using System;
using System.Net.Http;

namespace EW.Azure.Utilities
{
    public class IMDSUtility
    {
        // Query IMDS server and retrieve JSON result
        public static string JsonQuery(string path)
        {
            const string api_version = "2017-12-01";
            const string imds_server = "169.254.169.254";

            string imdsUri = "http://" + imds_server + "/metadata" + path + "?api-version=" + api_version + "&format=text";

            using (var httpClient = new HttpClient())
            {
                httpClient.DefaultRequestHeaders.Add("Metadata", "True");
                try
                {
                    HttpResponseMessage response = httpClient.GetAsync(imdsUri).Result;
                    if (response.StatusCode == System.Net.HttpStatusCode.NotFound)
                    {
                        return null;
                    }
                    response.EnsureSuccessStatusCode();
                    return response.Content.ReadAsStringAsync().Result;
                }
                catch (AggregateException ex)
                {
                    // handle response failures
                    Console.WriteLine("Request failed: " + ex.InnerException.Message);
                    throw;
                }
            }
        }
    }
}
