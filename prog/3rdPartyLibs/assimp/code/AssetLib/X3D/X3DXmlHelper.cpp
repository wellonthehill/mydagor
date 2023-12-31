#include "X3DXmlHelper.h"
#include "X3DImporter.hpp"

#include <assimp/ParsingUtils.h>

namespace Assimp {

bool X3DXmlHelper::getColor3DAttribute(XmlNode &node, const char *attributeName, aiColor3D &color) {
    eastl::string val;
    if (XmlParser::getStdStrAttribute(node, attributeName, val)) {
        eastl::vector<eastl::string> values;
        tokenize<eastl::string>(val, values, " ");
        if (values.size() != 3) {
            Throw_ConvertFail_Str2ArrF(node.name(), attributeName);
            return false;
        }
        auto it = values.begin();
        color.r = stof(*it++);
        color.g = stof(*it++);
        color.b = stof(*it);
        return true;
    }
    return false;
}

bool X3DXmlHelper::getVector2DAttribute(XmlNode &node, const char *attributeName, aiVector2D &color) {
    eastl::string val;
    if (XmlParser::getStdStrAttribute(node, attributeName, val)) {
        eastl::vector<eastl::string> values;
        tokenize<eastl::string>(val, values, " ");
        if (values.size() != 2) {
            Throw_ConvertFail_Str2ArrF(node.name(), attributeName);
            return false;
        }
        auto it = values.begin();
        color.x = stof(*it++);
        color.y = stof(*it);
        return true;
    }
    return false;
}

bool X3DXmlHelper::getVector3DAttribute(XmlNode &node, const char *attributeName, aiVector3D &color) {
    eastl::string val;
    if (XmlParser::getStdStrAttribute(node, attributeName, val)) {
        eastl::vector<eastl::string> values;
        tokenize<eastl::string>(val, values, " ");
        if (values.size() != 3) {
            Throw_ConvertFail_Str2ArrF(node.name(), attributeName);
            return false;
        }
        auto it = values.begin();
        color.x = stof(*it++);
        color.y = stof(*it++);
        color.z = stof(*it);
        return true;
    }
    return false;
}

bool X3DXmlHelper::getBooleanArrayAttribute(XmlNode &node, const char *attributeName, eastl::vector<bool> &boolArray) {
    eastl::string val;
    if (XmlParser::getStdStrAttribute(node, attributeName, val)) {
        eastl::vector<eastl::string> values;
        tokenize<eastl::string>(val, values, " ");
        auto it = values.begin();
        while (it != values.end()) {
            auto s = *it++;
            if (!s.empty())
                boolArray.push_back(s[0] == 't' || s[0] == '1');
            else
                Throw_ConvertFail_Str2ArrB(node.name(), attributeName);
        }
        return true;
    }
    return false;
}

bool X3DXmlHelper::getDoubleArrayAttribute(XmlNode &node, const char *attributeName, eastl::vector<double> &doubleArray) {
    eastl::string val;
    if (XmlParser::getStdStrAttribute(node, attributeName, val)) {
        eastl::vector<eastl::string> values;
        tokenize<eastl::string>(val, values, " ");
        auto it = values.begin();
        while (it != values.end()) {
            auto s = *it++;
            if (!s.empty())
                doubleArray.push_back(atof(s.c_str()));
            else
                Throw_ConvertFail_Str2ArrD(node.name(), attributeName);
        }
        return true;
    }
    return false;
}

bool X3DXmlHelper::getFloatArrayAttribute(XmlNode &node, const char *attributeName, eastl::vector<float> &floatArray) {
    eastl::string val;
    if (XmlParser::getStdStrAttribute(node, attributeName, val)) {
        eastl::vector<eastl::string> values;
        tokenize<eastl::string>(val, values, " ");
        auto it = values.begin();
        while (it != values.end()) {
            auto s = *it++;
            if (!s.empty())
                floatArray.push_back((float)atof(s.c_str()));
            else
                Throw_ConvertFail_Str2ArrF(node.name(), attributeName);
        }
        return true;
    }
    return false;
}

bool X3DXmlHelper::getInt32ArrayAttribute(XmlNode &node, const char *attributeName, eastl::vector<int32_t> &intArray) {
    eastl::string val;
    if (XmlParser::getStdStrAttribute(node, attributeName, val)) {
        eastl::vector<eastl::string> values;
        tokenize<eastl::string>(val, values, " ");
        auto it = values.begin();
        while (it != values.end()) {
            auto s = *it++;
            if (!s.empty())
                intArray.push_back((int32_t)atof(s.c_str()));
            else
                Throw_ConvertFail_Str2ArrI(node.name(), attributeName);
        }
        return true;
    }
    return false;
}

bool X3DXmlHelper::getStringListAttribute(XmlNode &node, const char *attributeName, eastl::list<eastl::string> &stringList) {
    eastl::string val;
    if (XmlParser::getStdStrAttribute(node, attributeName, val)) {
        eastl::vector<eastl::string> values;
        tokenize<eastl::string>(val, values, " ");
        auto it = values.begin();
        eastl::string currentConcat = "";
        bool inQuotes = false;
        while (it != values.end()) {
            auto s = *it++;
            if (!s.empty()) {
                if (inQuotes) {
                    if (*(s.rbegin()) == '"') {
                        stringList.push_back(currentConcat + s.substr(0, s.length() - 1));
                        currentConcat = "";
                        inQuotes = false;
                    } else {
                        currentConcat += " " + s;
                    }
                } else {
                    if (s[0] == '"') {
                        currentConcat = s.substr(1);
                        inQuotes = true;
                    } else {
                        stringList.push_back(s);
                    }
                }
            } else if (!inQuotes)
                Throw_ConvertFail_Str2ArrI(node.name(), attributeName);
        }
        if (inQuotes) Throw_ConvertFail_Str2ArrI(node.name(), attributeName);
        return true;
    }
    return false;
}

bool X3DXmlHelper::getStringArrayAttribute(XmlNode &node, const char *attributeName, eastl::vector<eastl::string> &stringArray) {
    eastl::list<eastl::string> tlist;

    if (getStringListAttribute(node, attributeName, tlist)) {
        if (!tlist.empty()) {
            stringArray.reserve(tlist.size());
            for (eastl::list<eastl::string>::iterator it = tlist.begin(); it != tlist.end(); ++it) {
                stringArray.push_back(*it);
            }
            return true;
        }
    }
    return false;
}

bool X3DXmlHelper::getVector2DListAttribute(XmlNode &node, const char *attributeName, eastl::list<aiVector2D> &vectorList) {
    eastl::string val;
    if (XmlParser::getStdStrAttribute(node, attributeName, val)) {
        eastl::vector<eastl::string> values;
        tokenize<eastl::string>(val, values, " ");
        if (values.size() % 2) Throw_ConvertFail_Str2ArrF(node.name(), attributeName);
        auto it = values.begin();
        while (it != values.end()) {
            aiVector2D tvec;

            tvec.x = (float)atof((*it++).c_str());
            tvec.y = (float)atof((*it++).c_str());
            vectorList.push_back(tvec);
        }
        return true;
    }
    return false;
}

bool X3DXmlHelper::getVector2DArrayAttribute(XmlNode &node, const char *attributeName, eastl::vector<aiVector2D> &vectorArray) {
    eastl::list<aiVector2D> tlist;

    if (getVector2DListAttribute(node, attributeName, tlist)) {
        if (!tlist.empty()) {
            vectorArray.reserve(tlist.size());
            for (eastl::list<aiVector2D>::iterator it = tlist.begin(); it != tlist.end(); ++it) {
                vectorArray.push_back(*it);
            }
            return true;
        }
    }
    return false;
}

bool X3DXmlHelper::getVector3DListAttribute(XmlNode &node, const char *attributeName, eastl::list<aiVector3D> &vectorList) {
    eastl::string val;
    if (XmlParser::getStdStrAttribute(node, attributeName, val)) {
        eastl::vector<eastl::string> values;
        tokenize<eastl::string>(val, values, " ");
        if (values.size() % 3 != 0) Throw_ConvertFail_Str2ArrF(node.name(), attributeName);
        auto it = values.begin();
        while (it != values.end()) {
            aiVector3D tvec;

            tvec.x = (float)atof((*it++).c_str());
            tvec.y = (float)atof((*it++).c_str());
            tvec.z = (float)atof((*it++).c_str());
            vectorList.push_back(tvec);
        }
        return true;
    }
    return false;
}

bool X3DXmlHelper::getVector3DArrayAttribute(XmlNode &node, const char *attributeName, eastl::vector<aiVector3D> &vectorArray) {
    eastl::list<aiVector3D> tlist;

    if (getVector3DListAttribute(node, attributeName, tlist)) {
        if (!tlist.empty()) {
            vectorArray.reserve(tlist.size());
            for (eastl::list<aiVector3D>::iterator it = tlist.begin(); it != tlist.end(); ++it) {
                vectorArray.push_back(*it);
            }
            return true;
        }
    }
    return false;
}

bool X3DXmlHelper::getColor3DListAttribute(XmlNode &node, const char *attributeName, eastl::list<aiColor3D> &colorList) {
    eastl::string val;
    if (XmlParser::getStdStrAttribute(node, attributeName, val)) {
        eastl::vector<eastl::string> values;
        tokenize<eastl::string>(val, values, " ");
        if (values.size() % 3 != 0) Throw_ConvertFail_Str2ArrF(node.name(), attributeName);
        auto it = values.begin();
        while (it != values.end()) {
            aiColor3D tvec;

            tvec.r = (float)atof((*it++).c_str());
            tvec.g = (float)atof((*it++).c_str());
            tvec.b = (float)atof((*it++).c_str());
            colorList.push_back(tvec);
        }
        return true;
    }
    return false;
}

bool X3DXmlHelper::getColor4DListAttribute(XmlNode &node, const char *attributeName, eastl::list<aiColor4D> &colorList) {
    eastl::string val;
    if (XmlParser::getStdStrAttribute(node, attributeName, val)) {
        eastl::vector<eastl::string> values;
        tokenize<eastl::string>(val, values, " ");
        if (values.size() % 4 != 0) Throw_ConvertFail_Str2ArrF(node.name(), attributeName);
        auto it = values.begin();
        while (it != values.end()) {
            aiColor4D tvec;

            tvec.r = (float)atof((*it++).c_str());
            tvec.g = (float)atof((*it++).c_str());
            tvec.b = (float)atof((*it++).c_str());
            tvec.a = (float)atof((*it++).c_str());
            colorList.push_back(tvec);
        }
        return true;
    }
    return false;
}

} // namespace Assimp
