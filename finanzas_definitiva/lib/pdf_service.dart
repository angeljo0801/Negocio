import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'models.dart';

class PdfService {
  static Future<Uint8List> report(String company,String title,String period,List<ReportRow> rows,String currency) async {
    final doc=pw.Document();
    doc.addPage(pw.MultiPage(pageFormat:PdfPageFormat.letter,build:(_)=>[
      pw.Text(company,style:pw.TextStyle(fontSize:18,fontWeight:pw.FontWeight.bold)),
      pw.Text(title,style:pw.TextStyle(fontSize:15,fontWeight:pw.FontWeight.bold)),pw.Text(period),pw.SizedBox(height:18),
      pw.TableHelper.fromTextArray(headers:['Concepto','Importe'],data:rows.map((r)=>[r.label,'$currency ${r.amount.toStringAsFixed(2)}']).toList(),headerDecoration:const pw.BoxDecoration(color:PdfColors.blueGrey800),headerStyle:pw.TextStyle(color:PdfColors.white,fontWeight:pw.FontWeight.bold),cellStyle:const pw.TextStyle(fontSize:10)),
      pw.SizedBox(height:16),pw.Text('Generado por Finanzas Definitiva',style:const pw.TextStyle(fontSize:8,color:PdfColors.grey)),
    ])); return doc.save();
  }
}
