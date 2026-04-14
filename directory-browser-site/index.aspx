<%@ Page Language="C#" AutoEventWireup="true" CodeFile="index.aspx.cs" Inherits="DirBrowser" %>

<!DOCTYPE html>
<html>

<head runat="server">
  <title>Downloads</title>

  <style>
    body {
      font-family: Segoe UI;
      font-size: 14px
    }

    table {
      border-collapse: collapse;
      width: 100%
    }

    td {
      padding: 4px 8px
    }

    tr:hover {
      background: #f0f0f0
    }

    a {
      text-decoration: none
    }

    .size {
      text-align: right;
      white-space: nowrap
    }

    .date {
      white-space: nowrap;
      color: #666
    }

    .breadcrumb {
      margin-bottom: 10px
    }
  </style>

</head>

<body>
  <form id="form1" runat="server">
    <asp:Literal ID="litOutput" runat="server"></asp:Literal>
  </form>
</body>

</html>
