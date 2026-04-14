using System;
using System.IO;
using System.Linq;
using System.Web.UI;

public partial class DirBrowser : Page
{
  protected void Page_Load(object sender, EventArgs e)
  {
    string basePath = Server.MapPath("~/");

    string rel = Request.RawUrl;

    if (rel.StartsWith("/public/", StringComparison.OrdinalIgnoreCase))
    {
      // allow anonymous
    }
    else
      if (!User.Identity.IsAuthenticated ||
          !User.IsInRole("MTG\\WebDownloads"))
      {
        Response.Clear();
        Response.StatusCode = 401;
        Response.End();
        return;
      }

    int q = rel.IndexOf('?');
    if (q >= 0)
      rel = rel.Substring(0, q);

    rel = rel.TrimStart('/');

    string physical = Path.Combine(basePath, rel);

    if (File.Exists(physical))
    {
      ServeFile(physical);
      return;
    }

    if (!Directory.Exists(physical))
    {
      Response.StatusCode = 404;
      return;
    }

    RenderDirectory(physical, rel);
  }

  void ServeFile(string file)
  {
    Response.Clear();
    Response.ContentType = "application/octet-stream";

    Response.AddHeader(
        "Content-Disposition",
        "attachment; filename=\"" + Path.GetFileName(file) + "\"");

    Response.TransmitFile(file);
    Response.End();
  }

  void RenderDirectory(string dir, string rel)
  {
    var dirs = new DirectoryInfo(dir)
        .GetDirectories()
        .Where(d => !IsHidden(d))
        .OrderByDescending(d => d.LastWriteTime);

    var files = new DirectoryInfo(dir)
        .GetFiles()
        .Where(f => !IsHidden(f))
        .Where(f => !IsBlockedExtension(f.Extension))
        .OrderByDescending(f => f.LastWriteTime);

    Write("<div class='breadcrumb'>");
    Write("<a href='/'>root</a>");

    if (!string.IsNullOrEmpty(rel))
    {
      string build = "";

      foreach (var p in rel.Split('/'))
      {
        build = Combine(build, p);
        Write(" / <a href='/" + build + "'>" + p + "</a>");
      }
    }

    Write("</div><hr/><table>");

    if (!string.IsNullOrEmpty(rel))
    {
      string parent = rel.Contains("/")
          ? rel.Substring(0, rel.LastIndexOf('/'))
          : "";

      Write("<tr><td>\uD83D\uDCC1 <a href='/" + parent + "'>[..]</a></td><td></td><td></td></tr>");
    }

    foreach (var d in dirs)
    {
      Write(
          "<tr>" +
          "<td>\uD83D\uDCC1 <a href='/" + Combine(rel, d.Name) + "'>" + d.Name + "</a></td>" +
          "<td>-</td>" +
          "<td>" + d.LastWriteTime.ToString("yyyy-MM-dd HH:mm") + "</td>" +
          "</tr>");
    }

    foreach (var f in files)
    {
      Write(
          "<tr>" +
          "<td>\uD83D\uDCC4 <a href='/" + Combine(rel, f.Name) + "'>" + f.Name + "</a></td>" +
          "<td>" + FormatSize(f.Length) + "</td>" +
          "<td>" + f.LastWriteTime.ToString("yyyy-MM-dd HH:mm") + "</td>" +
          "</tr>");
    }

    Write("</table>");
  }

  bool IsHidden(FileSystemInfo f)
  {
    return (f.Attributes & FileAttributes.Hidden) != 0
        || (f.Attributes & FileAttributes.System) != 0;
  }

  bool IsBlockedExtension(string ext)
  {
    ext = ext.ToLower();

    return ext == ".aspx"
        || ext == ".asax"
        || ext == ".ascx"
        || ext == ".config"
        || ext == ".cs"
        || ext == ".vb"
        || ext == ".master"
        || ext == ".pdb"
        || ext == ".ashx"
        || ext == ".asmx"
        || ext == ".svc";
  }

  string Combine(string a, string b)
  {
    if (string.IsNullOrEmpty(a))
      return b;

    return a.TrimEnd('/') + "/" + b;
  }

  string FormatSize(long bytes)
  {
    if (bytes > 1024L * 1024L * 1024L)
      return (bytes / 1024d / 1024d / 1024d).ToString("0.##") + " GB";

    if (bytes > 1024L * 1024L)
      return (bytes / 1024d / 1024d).ToString("0.##") + " MB";

    if (bytes > 1024L)
      return (bytes / 1024d).ToString("0.##") + " KB";

    return bytes + " B";
  }

  void Write(string s)
  {
    litOutput.Text += s;
  }
}
